#
# xmppd: a small XMPP server
# xmpp/tls.rb: handles TLS streams
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
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
require 'xmppd/xmpp/stream'

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
    # Ready the SSL stuff.
    cert = OpenSSL::X509::Certificate.new(File::read($config.listen.certfile))
    pkey = OpenSSL::PKey::RSA.new(File::read($config.listen.certfile))
    #pkey = OpenSSL::PKey::RSA.new(File::read('etc/ssl.key'))
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
    ctx.cert = cert
    ctx.key = pkey

    $-w = false # Turn warnings off because we get a meaningless SSL warning.
    tlssock = OpenSSL::SSL::SSLSocket.new(@socket, ctx)

    begin
        tlssock.accept
    rescue Exception => e
        @logger.unknown "-> TLS error: #{e}"
        @socket.close
        @state |= STATE_DEAD
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
