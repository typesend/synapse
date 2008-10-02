#
# synapse: a small XMPP server
# xmpp/stream.rb: XMPP stream library
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'digest/md5'
require 'idn'
require 'logger'
require 'openssl'
require 'resolv'
require 'socket'

#
# Import required xmppd modules.
#
require 'xmppd/log'
require 'xmppd/var'
require 'xmppd/xmpp/client'
require 'xmppd/xmpp/parser'

#
# The XMPP namespace.
#
module XMPP

#
# Our Stream class. This handles socket I/O, etc.
#
class Stream
    attr_accessor :socket, :auth
    attr_reader :host, :myhost, :resource, :rtime

    TYPE_NONE     = 0x00000000
    TYPE_CLIENT   = 0x00000001
    TYPE_SERVER   = 0x00000002

    STATE_NONE    = 0x00000000
    STATE_DEAD    = 0x00000001
    STATE_PLAIN   = 0x00000002
    STATE_ESTAB   = 0x00000004
    STATE_TLS     = 0x00000008
    STATE_SASL    = 0x00000010
    STATE_BIND    = 0x00000020
    STATE_SESSION = 0x00000040 # This is only here for state in Features::list().

    def initialize(host, type, myhost = nil)
        @socket = nil
        @host = IDN::Stringprep.nameprep(host)
        @recvq = ''
        @logger = nil
        @auth = nil
        @state = STATE_NONE
        @nonce = nil
        @resource = nil
        @rtime = Time.now.to_f

        parser_initialize

        if type == 'server'
            @type = TYPE_SERVER
        elsif type == 'client'
            @type = TYPE_CLIENT
        else
            raise ArgumentError, "type must be 'client' or 'server'"
        end

        unless myhost
            @myhost = $config.hosts.first
        end

        if $debug
            Dir.mkdir('var/streams') unless File.exists?('var/streams')

            if client?
                unless File.exists?('var/streams/c2s')
                    Dir.mkdir('var/streams/c2s')
                end

                @logger = Logger.new("var/streams/c2s/#{@host}")
            else
                unless File.exists?('var/streams/s2s')
                    Dir.mkdir('var/streams/s2s')
                end

                @logger = Logger.new("var/streams/s2s/#{@host}")
            end

            @logger.level = Logger::UNKNOWN
            @logger.progname = @host
            @logger.datetime_format = '%b %d %H:%M:%S '
        else
            @logger = MyLog::DeadLogger.new
        end
    end

    ######
    public
    ######

    def Stream.genid
        @@id_changed = Time.now.to_i
        @@id_counter = 0

        time = Time.now.to_i
        tid = Thread.new {}
        tid = tid.object_id
        @@id_counter += 1

        nid = (time << 48) | (tid << 16) | @@id_counter
        id = ''

        while nid > 0
            id += (nid & 0xFF).chr
            nid >>= 8
        end

        unless @@id_changed == time
            @@id_changed = time
            @@id_counter = 0
        end

        Digest::MD5.hexdigest(id)
    end

    def myhost=(value)
        @myhost = IDN::Stringprep.nameprep(value)
    end

    def established?
        return (STATE_ESTAB & @state != 0) ? true : false
    end

    def tls?
        return (STATE_TLS & @state != 0) ? true : false
    end

    def sasl?
        return (STATE_SASL & @state != 0) ? true : false
    end

    def bind?
        return (STATE_BIND & @state != 0) ? true : false
    end

    def session?
        return (STATE_SESSION & @state != 0) ? true : false
    end

    def dead?
        return (STATE_DEAD & @state != 0) ? true : false
    end

    def client?
        return (@type == TYPE_CLIENT) ? true : false
    end

    def server?
        return (@type == TYPE_SERVER) ? true : false
    end

    def close(try = true)
        # Close the stream.
        write '</stream:stream>' if try

        @socket.close unless @socket.closed?
        @state &= ~STATE_ESTAB
        @state |= STATE_DEAD

        return unless @resource

        # If they're online, make sure to broadcast that they're not anymore.
        if try and established?
            stanza = Client::PresenceStanza.new
            stanza.type = 'unavailable'
            stanza.xml = REXML::Element.new('presence')
            stanza.xml.add_attribute('type', 'unavailable')

            handle_type_unavailable(stanza)
        end

        @resource.user.delete_resource(@resource)
        @resouce = nil
    end

    def read
        begin
            if tls?
                data = @socket.readpartial(8192)
            else
                data = @socket.recv(8192)
            end
        rescue Errno::EAGAIN
            return
        rescue Exception => e
            @logger.unknown "-> read error: #{e}"
            close
            return
        end

        if data.empty?
            @logger.unknown "-> empty read"
            close
            return
        end

        string = ''
        string += "(#{@resource.name}) " if @resource
        string += '-> ' + data.gsub("\n", '')
        @logger.unknown string

        @recvq = data

        parse
    end

    def error(defined_condition, apperr = nil)
        err = REXML::Element.new('stream:error')
        na = REXML::Element.new(defined_condition)
        na.add_namespace('urn:ietf:params:xml:ns:xmpp-streams')
        err << na

        if apperr
            ae = REXML::Element.new(apperr['name'])
            ae.add_namespace('urn:xmpp:errors')
            ae.text = apperr['text'] if apperr['text']
            err << ae
        end

        establish unless established?

        write err
        close
    end

    def write(stanza)
        begin
            if tls?
                @socket.write(stanza.to_s)
            else
                @socket.send(stanza.to_s, 0)
            end
        rescue Errno::EAGAIN
            retry
        rescue Exception => e
            @logger.unknown "<- write error: #{e}"
            close(false)
            return
        else
            string = ''
            string += "(#{@resource.name}) " if @resource
            string += '<- ' + stanza.to_s
            @logger.unknown string
        end
    end

    #######
    private
    #######

    include XMPP::Parser

    #
    # First tries DNS SRV RR as per RFC3920.
    # On failure, falls back to regular DNS.
    #
    def resolve
        if client?
            rrname = '_xmpp-client._tcp.' + @host
        else
            rrname = '_xmpp-server._tcp.' + @host
        end

        resolver = Resolv::DNS.new
        original_recs = []
        weighted_recs = []

        # See whether Ruby has the DNS SRV RR class (RUBY_VERSION >= 1.8.3)
        type = nil
        srv_support = Resolv::DNS::Resource::IN.const_defined?('SRV')

        if srv_support
            type = Resolv::DNS::Resource::IN::SRV
        else
            type = Resolv::DNS::Resource::IN::ANY
        end

        begin
            resources = resolver.getresources(rrname, type)

            if srv_support
                resources.each do |x|
                    original_recs << { 'target'   => x.target,
                                       'port'     => x.port,
                                       'priority' => x.priority,
                                       'weight'   => x.weight }
                end
            else
                resources.each do |x|
                    classname = x.class.name.split('::').last
                    next unless classname == 'Type33_Class1'

                    priority, weight, port, target = x.data.unpack('n3a*')
                    pos = 0
                    addr = ''

                    until target[pos] == 0
                        addr += '.' unless pos == 0
                        len = target[pos]
                        pos += 1
                        addr += target[pos, len]
                        pos += len
                    end

                    original_recs << { 'target'   => addr,
                                       'port'     => port,
                                       'priority' => priority,
                                       'weight'   => weight }
                end
            end

            # Now we have all the info.
            equals = {}

            original_recs.each do |rec|
                prio = rec['priority']
                equals[prio] = [] unless equals.include?(prio)
                equals[prio] << rec
            end

            equals.keys.sort.each do |prio|
                eqrecs = equals[prio]

                if eqrecs.size <= 1
                    rec = eqrecs.first
                    weighted_recs << [ rec['target'], rec['port'] ]
                    next
                end

                sum = 0

                eqrecs.each { |rec| sum += rec['weight'] }

                factor = rand(sum + 1)
                sum = 0
                allzero = true

                eqrecs.each do |rec|
                    next if rec['weight'] == 0

                    sum += rec['weight']

                    if sum >= factor
                        weighted_recs << [ rec['target'], rec['port'] ]
                        allzero = false
                        break
                    end
                end

                if allzero
                    selectee = eqrecs[rand(eqrecs.size)]
                    weighted_recs << [ selectee['target'], selectee['port'] ]
                end
            end
        rescue Resolv::ResolvError
            if client?
                weighted_recs << [name, 5222]
            else
                weighted_recs << [name, 5269]
            end
        end

        if block_given?
            weighted_recs.each do |x|
                yield(x[0], x[1])
            end

            return nil
        else
            return weighted_recs.first[0, 2]
        end
    end
end

class ClientStream < Stream
    attr_reader :id

    def initialize(host, myhost = nil)
        super(host, 'client', myhost)
    end

    ######
    public
    ######

    def connect
        raise RuntimeError, "no client socket to connect with" unless @socket

        @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)

        $log.c2s.info "#{@host} -> TCP connection established"

        # We don't send the first stanza, so establish isn't
        # called until they try to establish a stream first.
    end

    def close(try = true)
        $log.c2s.info "#{@host} -> TCP connection closed"
        super(try)
    end

    def error(defined_condition, apperr = nil)
        $log.c2s.error "#{@host} -> #{defined_condition}"
        super(defined_condition, apperr)
    end

    #######
    private
    #######

    #
    # Manually build and send the opening stream XML.
    # We can't use REXML here because it closes all
    # of the tags on its own.
    #
    def establish
        @id = Stream.genid

        stanza = %(<?xml version='1.0'?>) +
                 %(<stream:stream ) +
                 %(xmlns='jabber:client' ) +
                 %(xmlns:stream='http://etherx.jabber.org/streams' ) +
                 %(from='#{@myhost}' ) +
                 %(id='#{@id}' ) +
                 %(version='1.0'>)

        write stanza

        if tls? and sasl?
            $log.c2s.info "#{@host} -> TLS/SASL stream established"
        elsif tls?
            $log.c2s.info "#{@host} -> TLS stream established"
        elsif sasl?
            $log.c2s.info "#{@host} -> SASL stream established"
        else
            $log.c2s.info "#{@host} -> stream established"
        end

        @state |= STATE_ESTAB
    end

    include XMPP::Client
end

class ServerStream < Stream
    attr_reader :host, :myhost, :socket

    def initialize(host, myhost = nil)
        super(host, 'server', myhost)
    end

    ######
    public
    ######

    def close(try = true)
        $log.s2s.info "#{@host} -> TCP connection closed"
        super(try)
    end

    def error(defined_condition, apperr = nil)
        $log.s2s.error "#{@host} -> #{defined_condition}"
        super(defined_condition, apperr)
    end

    #######
    private
    #######

    #      
    # Manually build and send the opening stream XML.
    # We can't use REXML here because it closes all  
    # of the tags on its own.                      
    #                        
    # ejabberd claims '1.0' but won't even let you
    # connect without an xmlns:db attribute. If
    # it's 1.0 then how does it expect servers
    # to initiate TLS connections?
    #
    def establish
        stanza = %(<?xml version='1.0'?>) +
                 %(<stream:stream to='#{@host}' ) +
                 %(from='#{@myhost}' ) +
                 %(xmlns='jabber:server' ) +
                 %(xmlns:stream='http://etherx.jabber.org/streams' ) +
                 %(xmlns:db='jabber:server:dialback' ) +
                 %(version='1.0'>)

        write stanza

        $log.s2s.info "#{@host} -> stream established"

        @state |= STATE_ESTAB
    end
end

#
# This class handles incoming s2s streams.
#
class ServerStreamIn < ServerStream
    attr_reader :host, :socket

    def initialize(host, socket)
        super(host)

        @host = IDN::Stringprep.nameprep(host)
        @socket = socket
    end

    ######
    public
    ######

    # This is an incoming socket, so stuff should be connected.
    def connect
        @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)

        $log.c2s.info "#{@host} -> TCP connection established"

        # We don't send the first stanza, so establish isn't
        # called until they try to establish a stream first.
    end
end

#
# This class handles outgoing s2s streams.
#
class ServerStreamOut < ServerStream
    attr_reader :host, :myhost, :socket

    def initialize(host, myhost)
        super(host, myhost)

        @host = IDN::Stringprep.nameprep(host)
        @myhost = IDN::Stringprep.nameprep(myhost)
    end

    ######
    public
    ######

    # This is an outgoing socket, so we need to connect out.
    def connect
        $log.s2s.info "#{@host}:5269 -> initiating TCP connection"

        addr, port = resolve

        begin
            @socket = TCPSocket.new(addr.to_s, port)
        rescue SocketError => e
            $log.s2s.info "#{host}:#{port} -> TCP connection failed"

            @state |= STATE_DEAD
        else
            @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)

            $log.s2s.info "#{addr}:#{port} -> TCP connection established"

            establish
        end
    end
end

end # module XMPP
