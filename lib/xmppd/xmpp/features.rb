#
# synapse: a small XMPP server
# xmpp/features.rb: handles stream features
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'rexml/document'

#
# Import required xmppd modules.
#
require 'xmppd/xmpp/stream'
require 'xmppd/xmpp/sasl'

#
# The XMPP namespace.
#
module XMPP

#
# The Features namespace.
#
module Features

extend self

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
end

def starttls
    starttls = REXML::Element.new('starttls')  
    starttls.add_namespace('urn:ietf:params:xml:ns:xmpp-tls')
    starttls.add_element(REXML::Element.new('required'))

    return starttls
end

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

def bind(type_client)
    recbind = REXML::Element.new('bind')
    recbind.add_namespace('urn:ietf:params:xml:ns:xmpp-bind')
    recbind.add_element(REXML::Element.new('required')) if type_client

    return recbind
end

# XXX - depreciated
def session
    sess = REXML::Element.new('session')
    sess.add_namespace('urn:ietf:params:xml:ns:xmpp-session')
    sess.add_element(REXML::Element.new('optional'))

    return sess
end

end # module Features
end # module XMPP
