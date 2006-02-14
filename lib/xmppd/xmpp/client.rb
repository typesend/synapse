#
# xmppd: a small XMPP server
# xmpp/client.rb: handles clients
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'idn'
require 'openssl'
require 'rexml/document'

#
# Import required xmppd modules.
#
require 'xmppd/var'
require 'xmppd/xmpp/features'

#
# The XMPP namespace.
#
module XMPP

#
# The Client namespace.
# This is meant to be a mixin to a Stream.
#
module Client

def handle_stream(elem)
    # First verify namespaces.
    unless elem.attributes['stream'] == 'http://etherx.jabber.org/streams'
        error('invalid-namespace')
        return
    end

    unless elem.attributes['xmlns'] == 'jabber:client'
        error('invalid-namespace')
        return
    end

    # Verify hostname.
    unless elem.attributes['to']
        error('bad-format')
        return
    end

    begin
        to_host = IDN::Stringprep.nameprep(elem.attributes['to'])
    rescue Exception
        error('bad-format')
        return
    end

    m = $config.hosts.find { |h| h == to_host }

    unless m
        error('host-unknown')
        return
    end

    @myhost = to_host

    # Seems to have passed all the requirements.
    establish

    # Send our feature list.
    XMPP::Features::list(self) if elem.attributes['version'] == '1.0'
end

def handle_starttls(elem)
    # First verify that we have an open stream.
    unless @established
        error('invalid-namespace')
        close
    end

    # Verify namespace.
    unless elem.attributes['xmlns'] == 'urn:ietf:params:xml:ns:xmpp-tls'
        error('invalid-namespace')
        close
    end

    # Send the go-ahead.
    xml = REXML::Document.new
    pro = REXML::Element.new('proceed')
    pro.add_namespace('urn:ietf:params:xml:ns:xmpp-tls')
    xml << pro

    write xml

    # Ready the SSL stuff.
    cert = OpenSSL::X509::Certificate.new(File::read($config.listen.certfile))
    pkey = OpenSSL::PKey::RSA.new(File::read($config.listen.certfile))
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
    ctx.cert = cert
    ctx.key = pkey

    $-w = false # Turn warnings off because we get a meaningless SSL warning.
    tlssock = OpenSSL::SSL::SSLSocket.new(@socket, ctx)
    $-w = true

    begin
        tlssock.accept
    rescue Exception => e
        @logger.unknown "-> TLS error: #{e}"
        close
        return
    end
           
    @socket = tlssock
    @tls = true
    @established = false

    @logger.unknown "-> TLS established"
end

end # module Client
end # module XMPP
