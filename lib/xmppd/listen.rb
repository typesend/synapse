#
# synapse: a small XMPP server
# listen.rb: handles listening sockets
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'socket'

#
# Import required xmppd modules.
#
require 'xmppd/auth'
require 'xmppd/var'
require 'xmppd/xmpp/stream'

# The Listen namespace.
module Listen

extend self

def init
    $config.listen.c2s.each do |h|
        nl = nil
        begin
            nl = Listen::Listener.new(h['host'], h['port'], 'client')
        rescue Exception => e
            puts 'xmppd: error aquiring socket ' +
                 "(#{h['host']}:#{h['port']}): #{e}"
            exit
        else
            $listeners << nl
        end
    end

    $config.listen.s2s.each do |h|
        nl = nil
        begin
            nl = Listen::Listener.new(h['host'], h['port'], 'server')
        rescue Exception => e
            puts 'xmppd: error aquiring socket ' +
                 "(#{h['host']}:#{h['port']}): #{e}"
            exit
        else
            $listeners << nl
        end
    end 
end

#
# Handles a new connection.
#
def handle_new(listener)
    # Accept the new connection.
    ns = listener.accept

    # This is to get around some silly IPv6 stuff.
    host = ns.peeraddr[3].sub('::ffff:', '')

    if listener.type == 'client'
        handle_client(ns, host)
    else
        handle_server(ns, host)
    end
end

#
# Handles a new connection on a server port.
#
def handle_server(socket, host)
    # Establish a new stream.
    nss = XMPP::ServerStreamIn.new(host, socket)
    nss.connect

    # Run through auth.
    auth = Auth::check(host)
    unless auth
        $log.s2s.warn "#{host} -> unauthorized connection"

        nss.error('not-authorized')
    else
        nss.auth = auth
        $connections << nss
    end
end

#
# Handles a new connection on a client port.
#
def handle_client(socket, host)
    # Establish a new stream.
    ncs = XMPP::ClientStream.new(host)
    ncs.socket = socket
    ncs.connect

    # Run through auth.
    auth = Auth::check(host)
    unless auth
        $log.c2s.warn "#{host} -> unauthorized connection"

        ncs.error('not-authorized')
    else
        ncs.auth = auth
        $connections << ncs
    end
end

class Listener < TCPServer
    attr_reader :host, :port, :type
 
    def initialize(host, port, type)
        @host = host
        @port = port

        if type != 'client' and type != 'server'
            raise ArgumentError, "type must be 'client' or 'server'"
        else
            @type = type
        end

        if host == '*'
            super(port)
        else
            super(host, port)
        end
    end
end

end # module Listen
