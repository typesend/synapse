#
# synapse: a small XMPP server
# xmpp/client.rb: handles clients
#
# Copyright (c) 2006-2008 Eric Will <rakaur@malkier.net>
#
# $Id$
#

# Import required Ruby modules.
require 'idn'
require 'rexml/document'

# Import required xmppd modules.
require 'xmppd/base64'
require 'xmppd/var'
require 'xmppd/xmpp/client_iq'
require 'xmppd/xmpp/client_presence'
require 'xmppd/xmpp/features'
require 'xmppd/xmpp/sasl'
require 'xmppd/xmpp/stream'
require 'xmppd/xmpp/tls'

# The XMPP namespace.
module XMPP

#
# The Client namespace.
# This is meant to be a mixin to a Stream.
#
module Client
include XMPP::SASL # For the SASL methods.
include XMPP::TLS  # For the TLS methods.

#
# Handle an incoming <stream> root element.
#
# elem:: [REXML::Element] parsed <stream> element
#
# return:: [XMPP::Stream] self
#
def handle_stream(elem)
    # Is the stream open?
    if established?
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

    # Do we serve this host?
    unless $config.hosts.include?(to_host)
        error('host-unknown')
        return
    end

    @myhost = to_host

    # Seems to have passed all the requirements.
    establish

    # Send our feature list.
    XMPP::Features.list(self) if elem.attributes['version'] == '1.0'

    self
end

#
# Handle an incoming <starttls/> stanza.
#
# elem:: [REXML::Element] parsed <starttls/> stanza
#
# return:: [XMPP::Stream] self
#
def handle_starttls(elem)
    # First verify that we have an open stream.
    unless established?
        error('invalid-namespace')
        return
    end

    # Verify namespace.
    unless elem.attributes['xmlns'] == 'urn:ietf:params:xml:ns:xmpp-tls'
        fai = REXML::Element.new('failure')
        fai.add_namespace('urn:ietf:params:xml:ns:xmpp-tls')

        write fai
        
        close
        return
    end

    # Send the go-ahead.
    pro = REXML::Element.new('proceed')
    pro.add_namespace('urn:ietf:params:xml:ns:xmpp-tls')

    write pro

    starttls

    self
end

#
# Handle an incoming <auth/> stanza.
#
# elem:: [REXML::Element] parsed <auth/> stanza
#
# return:: [XMPP::Stream] self
#
def handle_auth(elem)
    # First verify that we have an open stream.
    unless established?
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
        fai = REXML::Element.new('failure')
        fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
        fai << REXML::Element.new('invalid-mechanism')

        write fai

        close
        return
    end
    
    # If they're using PLAIN, we can finish up right here.
    if elem.attributes['mechanism'] == 'PLAIN'
        authzid, authcid, passwd = Base64.decode64(elem.text).split("\000")
        authzid = authcid + '@' + @myhost if authzid.empty?

        unless DB::User.auth(authzid, passwd, true)
            fai = REXML::Element.new('failure')
            fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
            fai << REXML::Element.new('not-authorized')

            write fai

            close
            return
        end
        
        suc = REXML::Element.new('success')
        suc.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
        
        write suc
        
        @state &= ~Stream::STATE_ESTAB
        @state |= Stream::STATE_SASL
        
        @jid = authzid

        @logger.unknown '-> SASL established'

        return
    end

    @nonce = Stream.genid
    chal   = 'nonce="%s",qop="auth",charset=utf-8,algorithm=md5-sess' % @nonce
    chal   = "realm=#{@myhost}," + chal
    chal   = Base64.encode64(chal)

    chal.gsub!("\n", '')

    challenge      = REXML::Element.new('challenge')
    challenge.text = chal

    challenge.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')

    write challenge

    self
end

#
# Handle an incoming <response/> stanza.
#
# elem:: [REXML::Element] parsed <response/> stanza
#
# return:: [XMPP::Stream] self
#
def handle_response(elem)
    # First verify that we have an open stream.
    unless established?
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
        if sasl?
            suc = REXML::Element.new('success')
            suc.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')

            write suc

            @state &= ~Stream::STATE_ESTAB

            @logger.unknown '-> SASL established'

            return
        else
            fai = REXML::Element.new('failure')
            fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
            fai << REXML::Element.new('incorrect-encoding')

            write fai

            close
            return
        end
    end

    #
    # I know this sucks, but you have the guy that designed SASL's DIGEST-MD5
    # blame for it. For some reason he decided it'd be a good idea to allow the
    # 'cnonce' field be able to consist of ANYTHING, which makes tokenizing
    # this string a bitch.
    #
    # This took four people on the jdev mailing list a while to sort out.
    #
    resp = Base64.decode64(elem.text)
    re = /((?:[\w-]+)\s*=\s*(?:(?:"[^"]+")|(?:[^,]+)))/
    
    response = {}
    resp.scan(re) do |kv|
        k, v = kv[0].split('=', 2)
        v.gsub!(/^"(.*)"$/, '\1')
        response[k] = v
    end

    # Is our key the same?
    unless response['nonce'] == @nonce
        fai = REXML::Element.new('failure')
        fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
        fai << REXML::Element.new('incorrect-encoding')

        write fai

        close
        return
    end

    # Is the realm right?
    unless response['realm'] == @myhost
        fai = REXML::Element.new('failure')       
        fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
        fai << REXML::Element.new('incorrect-encoding')

        write fai

        close
        return
    end

    # Is the digest-uri right?
    unless response['digest-uri'] == 'xmpp/' + @myhost
        fai = REXML::Element.new('failure')
        fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
        fai << REXML::Element.new('incorrect-encoding')

        write fai

        close
        return
    end

    # Start SASL.
    startsasl(response)

    self
end

#
# Handle an incoming <abort/> stanza.
#
# elem:: [REXML::Element] parsed <abort/> stanza
#
# return:: [XMPP::Stream] self
#
def handle_abort(elem)
    # First verify that we have an open stream.
    unless established?
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
    
    fai = REXML::Element.new('failure')
    fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
    fai << REXML::Element.new('aborted')

    write fai

    self
end

end # module Client
end # module XMPP
