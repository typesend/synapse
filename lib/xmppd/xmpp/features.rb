#
# synapse: a small XMPP server
# xmpp/features.rb: handles stream features
#
# Copyright (c) 2006-2008 Eric Will <rakaur@malkier.net>
#
# $Id$
#

# Import required Ruby modules.
require 'rexml/document'

# Import required xmppd modules.
require 'xmppd/xmpp'

# The XMPP namespace.
module XMPP

# The Features namespace.
module Features

extend self

#
# Send the <stream:features/> stanza.
# This changes as the stream's context changes.
#
# stream:: [XMPP::Stream] the stream to send to
#
# return:: [XMPP::Stream] the same stream
#
def list(stream)
    feat = REXML::Element.new('stream:features')

    # They're not in TLS.
    if not stream.tls?
        # They're not required to have TLS, so advertise SASL.
        feat << sasl if stream.auth.plain && !stream.auth.legacy_auth

        # They're required to have TLS, but they're not in it,
        # so advertise that.
        feat << starttls if !stream.auth.plain

    # They're in TLS, but not SASL.
    elsif not stream.sasl?
        feat << sasl if !stream.auth.legacy_auth 
        feat << register if stream.client?

    # They're in both.
    else
        if stream.client?
            feat << bind(true) unless stream.bind?
        else # Servers aren't required to bind a resource.
            feat << bind(false) unless stream.bind?
        end
        
        # Session has been removed in the new draft RFC.
        feat << session unless stream.session?
    end

    stream.write feat

    stream
end

#
# Build the <starttls/> element for <stream:features/>.
#
# return:: [REXML::Element] <starttls/> element
#
def starttls
    starttls = REXML::Element.new('starttls')  
    starttls.add_namespace('urn:ietf:params:xml:ns:xmpp-tls')
    starttls.add_element(REXML::Element.new('required'))

    return starttls
end

#
# Build the <mechanisms/> element for <stream:features/>.
#
# return:: [REXML::Element] <mechanisms/> element
#
def sasl
    mechs = REXML::Element.new('mechanisms')
    mechs.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')
    
    SASL::MECHANISMS.each do |mech|
        mechxml = REXML::Element.new('mechanism')
        mechxml.text = mech
        mechs << mechxml
    end

    return mechs
end

#
# Build the <bind/> element for <stream:features/>.
#
# return:: [REXML::Element] <bind/> element
#
def bind(type_client)
    recbind = REXML::Element.new('bind')
    recbind.add_namespace('urn:ietf:params:xml:ns:xmpp-bind')
    recbind.add_element(REXML::Element.new('required')) if type_client

    return recbind
end

# XXX - DEPRECIATED
#
# Build the <session/> element for <stream:features/>.
#
# return:: [REXML::Element] <session/> element
#
def session
    sess = REXML::Element.new('session')
    sess.add_namespace('urn:ietf:params:xml:ns:xmpp-session')
    sess.add_element(REXML::Element.new('optional'))

    return sess
end

#
# Build the <register/> element for <stream:features/>.
#
# return:: [REXML::Element] <register/> element
#
def register
    reg = REXML::Element.new('register')
    reg.add_namespace('http://jabber.org/features/iq-register')

    return reg
end

end # module Features
end # module XMPP
