#
# xmppd: a small XMPP server
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
require 'xmppd/xmpp/stream'
require 'xmppd/var'

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

class Listener < TCPServer
    attr_reader :host, :port, :type
 
    def initialize(host, port, type)
        @host = host
        @port = port

        if type != 'client' && type != 'server'
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
