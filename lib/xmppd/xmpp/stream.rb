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
require 'io/nonblock'
require 'resolv'
require 'rexml/document'
require 'socket'

#
# Import required xmppd modules.
#
require 'xmppd/var'

#
# The XMPP namespace.
#
module XMPP

#
# The REXML Listener class.
#
class StreamListener
    def tag_start(name, attrs)
    end

    def tag_end(name)
    end

    def text(text)
    end
end

#
# Our Stream class. This handles socket I/O, etc.
#
class Stream
    CLIENT_PORT = 5222
    SERVER_PORT = 5269

    attr_accessor :socket
    attr_reader :host, :type, :realhost

    def initialize(host, type)
        @socket = nil
        @host = host
        @dead = false

        if type != 'client' && type != 'server'
            raise ArgumentError, "type must be 'client' or 'server'"
        else
            @type = type
        end
    end

    ######
    public
    ######

    def dead?
        @dead
    end

    def close
        @socket.shutdown
        @socket.close
        @dead = true
    end

    #######
    private
    #######

    def send(stanza)
        begin
            @socket.send(stanza.to_s, 0)
        rescue Errno::EAGAIN
            retry
        end
    end

    #
    # First tries DNS SRV RR as per RFC3920.
    # On failure, falls back to regular DNS.
    #
    def resolve
        if @type == 'client'
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
            if @type == 'client'
                weighted_recs << [name, CLIENT_PORT]
            else
                weighted_recs << [name, SERVER_PORT]
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
    def initialize(host)
        super(host, 'client')
    end

    ######
    public
    ######

    def connect         
        addr, port = resolve
                    
        begin
            @socket = TCPSocket.new(addr.to_s, port)
        rescue SocketError => e
            @dead = true  
        else
            @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
            @socket.nonblock = true
                                       
            establish
        end
    end

    def send(stanza)
        $log.c2s.debug "#{@host} <- #{stanza.to_s}"
        super(stanza)
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
                 %(<stream:stream to='#{@host}' ) +
                 %(xmlns='jabber:client' ) +
                 %(xmlns:stream='http://etherx.jabber.org/streams' ) +
                 %(version='1.0' ) +
                 %(xml:lang='en'>)

        send(stanza)
    end
end

class ServerStream < Stream
    attr_reader :myhost

    def initialize(host, myhost)
        super(host, 'server')
        @myhost = myhost
    end

    ######
    public
    ######

    def connect
        raise RuntimeError, 'no socket set to connect' unless @socket

        establish
    end

    def send(stanza)
        $log.s2s.debug "#{@host} <- #{stanza.to_s}"
        super(stanza)
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
                 %(<stream:stream to='#{@host}' ) +
                 %(from='#{@myhost}' ) +
                 %(xmlns='jabber:server' ) +
                 %(xmlns:stream='http://etherx.jabber.org/streams' ) +
                 %(version='1.0' ) +
                 %(xml:lang='en'>)

        send(stanza)
    end
end

end # module XMPP
