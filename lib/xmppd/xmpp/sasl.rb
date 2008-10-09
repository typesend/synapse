#
# synapse: a small XMPP server
# xmpp/sasl.rb: handles SASL streams
#
# Copyright (c) 2006-2008 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'digest/md5'
require 'rexml/document'

#
# Import required xmppd modules.
#
require 'xmppd/base64'
require 'xmppd/db'
require 'xmppd/xmpp'

#
# The XMPP namespace.
#
module XMPP

#
# The SASL namespace.
# This is meant to be a mixin to a Stream.
#
module SASL

MECHANISMS = ['DIGEST-MD5', 'PLAIN']

def h(s)
    Digest::MD5.digest(s)
end

def hh(s)
    Digest::MD5.hexdigest(s)
end

def startsasl(response)
    node   = IDN::Stringprep.nodeprep(response['username'])
    domain = IDN::Stringprep.nameprep(response['realm'])
    @jid   = node + '@' + domain
    user   = DB::User.users[@jid]

    unless user
        fai = REXML::Element.new('failure')
        fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
        fai << REXML::Element.new('not-authorized')

        write fai

        close
        return
    end

    a1_h = user.password

    # Compute response and see if it matches.
    # Sorry, but there's no pretty way to do this.
    a1 = "%s:%s:%s" % [a1_h, response['nonce'], response['cnonce']]
    a2 = "AUTHENTICATE:%s" % response['digest-uri']

    myresp = "%s:%s:%s:%s:auth:%s" % [hh(a1), response['nonce'],
                                      response['nc'], response['cnonce'],
                                      hh(a2)]
    myresp = hh(myresp)

    # Are they authorized?
    unless myresp == response['response']
        fai = REXML::Element.new('failure')
        fai.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
        fai << REXML::Element.new('not-authorized')

        write fai

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

    chal = REXML::Element.new('challenge')
    chal.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
    chal.text = rspauth

    @state |= Stream::STATE_SASL

    write chal
end

end # module SASL
end # module XMPP
