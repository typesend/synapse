#
# synapse: a small XMPP server
# xmpp/tls.rb: handles TLS streams
#
# Copyright (c) 2006-2008 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'openssl'

#
# Import required xmppd modules.
#
require 'xmppd/xmpp'

#
# The XMPP namespace.
#
module XMPP

#
# The TLS namespace.
# This is meant to be a mixin to a Stream.
#
module TLS

extend self

def starttls
    $-w = false # Turn warnings off because we get a meaningless SSL warning.
    tlssock = OpenSSL::SSL::SSLSocket.new(@socket, $ctx)

    begin
        tlssock.accept
    rescue Exception => e
        @logger.unknown "-> TLS error: #{e}"
        @socket.close
        @state |= Stream::STATE_DEAD
        return
    end
    $-w = true # Get them back.

    @socket = tlssock
    @state |= Stream::STATE_TLS
    @state &= ~Stream::STATE_ESTAB

    @logger.unknown "-> TLS established"
end

end # module TLS
end # module XMPP
