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
require 'base64'
require 'digest/md5'
require 'idn'
require 'openssl'
require 'rexml/document'

#
# Import required xmppd modules.
#
require 'xmppd/var'
require 'xmppd/xmpp/features'
require 'xmppd/xmpp/stream'

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
    unless Stream::STATE_ESTAB & @state != 0
        error('invalid-namespace')
        return
    end

    # Verify namespace.
    unless elem.attributes['xmlns'] == 'urn:ietf:params:xml:ns:xmpp-tls'
        error('invalid-namespace')
        return
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
    @state |= Stream::STATE_TLS
    @state &= ~Stream::STATE_ESTAB

    @logger.unknown "-> TLS established"
end

def handle_auth(elem)
    # First verify that we have an open stream.
    unless Stream::STATE_ESTAB & @state != 0
        error('invalid-namespace')
        return
    end

    # Verify namespace.
    unless elem.attributes['xmlns'] == 'urn:ietf:params:xml:ns:xmpp-sasl'
        error('invalid-namespace')
        return
    end

    # Make sure they're using a mechanism we support.
    unless elem.attributes['mechanism'] == 'DIGEST-MD5'
        xml = REXML::Document.new
        fai = REXML::Element.new('failure')
        fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
        fai << REXML::Element.new('invalid-mechanism')
        xml << fai

        write xml

        close
        return
    end

    @nonce = rand(rand(1000000)).to_s
    chal = 'nonce="%s",qop="auth",charset=utf-8,algorithm=md5-sess' % @nonce
    chal = Base64.encode64(chal)
    chal.gsub!("\n", '')

    xml = REXML::Document.new
    challenge = REXML::Element.new('challenge')
    challenge.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
    challenge.text = chal
    xml << challenge

    write xml
end

def handle_response(elem)
    # First verify that we have an open stream.
    unless Stream::STATE_ESTAB & @state != 0
        error('invalid-namespace')
        return
    end

    # Verify that we've sent a challenge.
    unless @nonce
        error('invalid-namespace')
    end

    # Verify namespace.
    unless elem.attributes['xmlns'] == 'urn:ietf:params:xml:ns:xmpp-sasl'
        error('invalid-namespace')
        return
    end

    # Decode the response.
    unless elem.has_text?
        if Stream::STATE_SASL & @state != 0
            xml = REXML::Document.new
            suc = REXML::Element.new('success')
            suc.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
            xml << suc

            write xml

            @logger.unknown '-> SASL established'

            return
        else
            xml = REXML::Document.new
            fai = REXML::Element.new('failure')
            fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
            fai << REXML::Element.new('incorrect-encoding')
            xml << fai

            write xml

            close

            return
        end
    end

    resp = Base64.decode64(elem.text)
    resp = resp.split(',')

    response = {}
    resp.each do |kv|
        k, v = kv.split('=')
        v.gsub!(/^"/, '')
        v.gsub!(/"$/, '')

        response[k] = v

    end

    # Is our key the same?
    unless response['nonce'] == @nonce
        xml = REXML::Document.new
        fai = REXML::Element.new('failure')
        fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
        fai << REXML::Element.new('incorrect-encoding')
        xml << fai

        write xml

        close
        return
    end

    # Is the realm right?
    unless response['realm'] == @myhost
        xml = REXML::Document.new
        fai = REXML::Element.new('failure')       
        fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
        fai << REXML::Element.new('incorrect-encoding')
        xml << fai

        write xml

        close
        return
    end

    # Is the digest-uri right?
    unless response['digest-uri'] == 'xmpp/' + @myhost
        xml = REXML::Document.new
        fai = REXML::Element.new('failure')
        fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
        fai << REXML::Element.new('incorrect-encoding')
        xml << fai

        write xml

        close
        return
    end

    # Compute response and see if it matches.
    # Sorry, but there's no pretty way to do this.
    a1_h = "%s:%s:%s" % [response['username'], response['realm'], 'VeMasa5ew']
    a1_h = h(a1_h)

    a1 = "%s:%s:%s" % [a1_h, response['nonce'], response['cnonce']]
    a2 = "AUTHENTICATE:%s" % response['digest-uri']

    myresp = "%s:%s:%s:%s:auth:%s" % [hh(a1), response['nonce'],
                                      response['nc'], response['cnonce'],
                                      hh(a2)]
    myresp = hh(myresp)

    # Are they authorized?
    unless myresp == response['response']
        xml = REXML::Document.new
        fai = REXML::Element.new('failure')
        fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
        fai << REXML::Element.new('not-authorized')
        xml << fai

        write xml

        close
        return
    end

    # Now do it all over again.
    a2 = ":%s" % response['digest-uri']
    rspauth = "%s:%s:%s:%s:auth:%s" % [hh(a1), response['nonce'],
                                        response['nc'], response['cnonce'],
                                        hh(a2)]

    rspauth = "rspauth=%s" % hh(rspauth)
    rspauth = Base64.encode64(rspauth)
    rspauth.gsub!("\n", '')

    xml = REXML::Document.new
    chal = REXML::Element.new('challenge')
    chal.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
    chal.text = rspauth
    xml << chal

    @state |= Stream::STATE_SASL

    write xml
end

def h(s); Digest::MD5.digest(s); end
def hh(s); Digest::MD5.hexdigest(s); end

end # module Client
end # module XMPP
