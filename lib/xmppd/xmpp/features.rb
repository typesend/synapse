#
# xmppd: a small XMPP server
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
    xml = REXML::Document.new
    feat = REXML::Element.new('stream:features')

    # They're not in TLS.
    if Stream::STATE_TLS & stream.state == 0
        # They're not required to have TLS, so advertise SASL.
        feat << sasl if stream.auth.plain && !stream.auth.legacy_auth

        # They're required to have TLS, but they're not in it,
        # so advertise that.
        feat << starttls if !stream.auth.plain

    # They're in TLS, but not SASL.
    elsif Stream::STATE_SASL & stream.state == 0
        feat << sasl if !stream.auth.legacy_auth 

    # They're in both.
    else
        feat << bind if Stream::STATE_BIND & stream.state == 0
        feat << session if Stream::STATE_SESSION & stream.state == 0
    end

    xml << feat
    stream.write(xml)
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

def bind
    recbind = REXML::Element.new('bind')
    recbind.add_namespace('urn:ietf:params:xml:ns:xmpp-bind')

    return recbind
end

def session
    sess = REXML::Element.new('session')
    sess.add_namespace('urn:ietf:params:xml:ns:xmpp-session')

    return sess
end

end # module Features
end # module XMPP
