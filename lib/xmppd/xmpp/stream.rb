#
# xmppd: a small XMPP server
# xmpp/stream.rb: XMPP stream library
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'idn'
require 'io/nonblock'
require 'logger'
require 'openssl'
require 'resolv'
require 'rexml/document'
require 'socket'

#
# Import required xmppd modules.
#
require 'xmppd/log'
require 'xmppd/var'
require 'xmppd/xmpp/client'

#
# The XMPP namespace.
#
module XMPP

#
# Our Stream class. This handles socket I/O, etc.
#
class Stream
    attr_accessor :socket, :auth
    attr_reader :host, :myhost, :type, :state

    TYPE_NONE   = 0x00000000
    TYPE_CLIENT = 0x00000001
    TYPE_SERVER = 0x00000002

    STATE_NONE  = 0x00000000
    STATE_DEAD  = 0x00000001
    STATE_PLAIN = 0x00000002
    STATE_ESTAB = 0x00000004
    STATE_TLS   = 0x00000008
    STATE_SASL  = 0x00000010

    def initialize(host, type, myhost = nil)
        @socket = nil
        @host = IDN::Stringprep.nameprep(host)
        @recvq = []
        @logger = nil
        @auth = nil
        @state = STATE_NONE

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

            if @type == TYPE_CLIENT
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

    def myhost=(value)
        @myhost = IDN::Stringprep.nameprep(value)
    end

    def dead?
        if STATE_DEAD & @state != 0
            true
        else
            false
        end
    end

    def close
        # Close the stream.
        write '</stream:stream>'

        @socket.close
        @state |= STATE_DEAD
    end

    def read
        begin
            if STATE_TLS & @state != 0
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
            close
            return
        end

        @logger.unknown "-> #{data}"

        @recvq << data

        parse
    end

    def error(defined_condition)
        xml = REXML::Document.new
        err = REXML::Element.new('stream:error')
        na = REXML::Element.new(defined_condition)
        na.add_namespace('urn:ietf:params:xml:ns:xmpp-streams')
        err << na
        xml << err

        establish unless STATE_ESTAB & @state != 0

        write(xml)
        close     
    end


    #######
    private
    #######

    def write(stanza)
        begin
            if STATE_TLS & @state != 0
                @socket.write(stanza.to_s)
            else
                @socket.send(stanza.to_s, 0)
            end
        rescue Errno::EAGAIN
            retry
        rescue Exception => e
            @logger.unknown "<- write error: #{e}"

            # Can't use `close` here because it will just
            # call `write` for </stream:stream> which will just
            # call `close` until we get a stack overflow.
            @socket.close
            @state |= STATE_DEAD

            return
        end
    end

    def parse
        @recvq.each do |stanza|
            begin
                xml = REXML::Document.new(stanza)
            rescue REXML::ParseException => e
                if e.message =~ /stream:stream/ # Closing stream tag.
                    close
                    return
                else
                    error('xml-not-well-formed')
                    return
                end
            end

            xml.elements.each do |elem|
                methname = "handle_#{elem.name}"
                methname.sub!(':', '_')

                unless respond_to? methname
                    if @type == TYPE_CLIENT
                        $log.c2s.error "Unknown stanza from #{@host}: " +
                                       "'#{elem.name}' (no '#{methname}')"
                    else
                        $log.s2s.error "Unknown stanza from #{@host}: " +
                                       "'#{elem.name}' (no '#{methname}')"
                    end

                    error('xml-not-well-formed')
                    return
                end

                send(methname, elem)
            end
        end

        @recvq = []
    end

    #
    # First tries DNS SRV RR as per RFC3920.
    # On failure, falls back to regular DNS.
    #
    def resolve
        if @type == TYPE_CLIENT
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
            if @type == TYPE_CLIENT
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
        @id = rand(rand(1000000))
    end

    ######
    public
    ######

    def connect
        raise RuntimeError, "no client socket to connect with" unless @socket

        @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
        @socket.nonblock = true

        $log.c2s.info "#{@host} -> TCP connection established"

        # We don't send the first stanza, so establish isn't
        # called until they try to establish a stream first.
    end

    def write(stanza)
        @logger.unknown "<- #{stanza.to_s}"
        super(stanza)
    end

    def close
        $log.c2s.info "#{@host} -> TCP connection broken"
        super
    end

    def error(defined_condition)
        $log.c2s.error "#{@host} -> #{defined_condition}"
        super(defined_condition)
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
        stanza = %(<?xml version='1.0'?>) +
                 %(<stream:stream ) +
                 %(xmlns='jabber:client' ) +
                 %(xmlns:stream='http://etherx.jabber.org/streams' ) +
                 %(from='#{@myhost}' ) +
                 %(id='#{@id}' ) +
                 %(version='1.0'>)

        write(stanza)

        if STATE_TLS & @state != 0
            $log.c2s.info "#{@host} -> TLS stream established"
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

    def write(stanza)
        @logger.unknown "<- #{stanza.to_s}"
        super(stanza)
    end

    def close
        $log.s2s.info "#{@host} -> TCP connection broken"
        super
    end

    def error(defined_condition)
        $log.s2s.error "#{@host} -> #{defined_condition}"
        super(defined_condition)
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

        write(stanza)

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
        @socket.nonblock = true

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
            @socket.nonblock = true

            $log.s2s.info "#{addr}:#{port} -> TCP connection established"

            establish
        end
    end
end

end # module XMPP
