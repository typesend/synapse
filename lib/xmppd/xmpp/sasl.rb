#
# xmppd: a small XMPP server
# xmpp/sasl.rb: handles SASL streams
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
require 'rexml/document'

#
# Import required xmppd modules.
#
require 'xmppd/xmpp/stream'

#
# The XMPP namespace.
#
module XMPP

#
# The SASL namespace.
# This is meant to be a mixin to a Stream.
#
module SASL

def h(s)
    Digest::MD5.digest(s)
end

def hh(s)
    Digest::MD5.hexdigest(s)
end

def startsasl(response)
    # XXX - do a lookup on the username to grab the password.
    #       natrually i need to write a database about now. sigh.
    #       password needs to be stored as:
    #           h({ "username", ":", "realm", ":", "password" })
    #
    #       and then for non-sasl we'll just have to pick out
    #       the realm and check against that.
    #a1_h = password lookup

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

end # module SASL
end # module XMPP