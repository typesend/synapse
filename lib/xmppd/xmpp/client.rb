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
require 'idn'
require 'rexml/document'

#
# Import required xmppd modules.
#
require 'xmppd/var'
require 'xmppd/xmpp/client_iq'
require 'xmppd/xmpp/features'
require 'xmppd/xmpp/sasl'
require 'xmppd/xmpp/stream'
require 'xmppd/xmpp/tls'

#
# The XMPP namespace.
#
module XMPP

#
# The Client namespace.
# This is meant to be a mixin to a Stream.
#
module Client
include XMPP::SASL
include XMPP::TLS

def handle_stream(elem)
    # Is the stream open?
    if Stream::STATE_ESTAB & @state != 0
        error('invalid-namespace')
        return
    end

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
        xml = REXML::Document.new
        fai = REXML::Element.new('failure')
        fai.add_namespace('urn:ietf:params:xml:ns:xmpp-tls')
        xml << fai

        write xml
        
        close
        return
    end

    # Send the go-ahead.
    xml = REXML::Document.new
    pro = REXML::Element.new('proceed')
    pro.add_namespace('urn:ietf:params:xml:ns:xmpp-tls')
    xml << pro

    write xml

    starttls
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
    unless SASL::MECHANISMS.include? elem.attributes['mechanism']
        xml = REXML::Document.new
        fai = REXML::Element.new('failure')
        fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
        fai << REXML::Element.new('invalid-mechanism')
        xml << fai

        write xml

        close
        return
    end
    
    # If they're using PLAIN, we can finish up right here.
    if elem.attributes['mechanism'] == 'PLAIN'
        authzid, authcid, passwd = Base64.decode64(elem.text).split("\000")
        authzid = authcid + '@' + @myhost if authzid.empty?

        unless DB::User.auth(authzid, passwd, true)
            xml = REXML::Document.new
            fai = REXML::Element.new('failure')
            fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
            fai << REXML::Element.new('not-authorized')
            xml << fai

            write xml

            close
            return
        end
        
        xml = REXML::Document.new
        suc = REXML::Element.new('success')
        suc.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
        #suc.text = '=' # According to the RFC, this is how it's done. Psi doesn't like it, and no one else seems to care...
        xml << suc
        
        write xml
        
        @state &= ~Stream::STATE_ESTAB
        @state |= Stream::STATE_SASL
        
        @jid = authzid

        @logger.unknown '-> SASL established'

        return
    end

    @nonce = Stream.genid
    chal = 'nonce="%s",qop="auth",charset=utf-8,algorithm=md5-sess' % @nonce
    chal = "realm=#{@myhost}," + chal
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

            @state &= ~Stream::STATE_ESTAB

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

    # Start SASL.
    startsasl(response)
end

def handle_abort(elem)
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
    
    xml = REXML::Document.new
    fai = REXML::Element.new('failure')
    fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
    fai << REXML::Element.new('aborted')
    xml << fai

    write xml
end

end # module Client
end # module XMPP
