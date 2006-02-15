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

    unless Stream::STATE_TLS & stream.state != 0
        # They're not required to have TLS, so advertise SASL.
        feat << sasl if stream.auth.plain && !stream.auth.legacy_auth

        # They're required to have TLS, but they're not in it,
        # so advertise that.
        feat << starttls if !stream.auth.plain
    else
        # They're in TLS, and are required to use SASL,
        # so advertise that.
        feat << sasl if !stream.auth.legacy_auth
    end

    # They're not required to do TLS, or SASL, so they don't
    # need a feature list.
    return unless feat.has_elements?

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
                            
    mech_1 = REXML::Element.new('mechanism')
    mech_1.text = 'DIGEST-MD5'
    mechs << mech_1     
                            
    mech_2 = REXML::Element.new('mechanism')
    mech_2.text = 'PLAIN'
    mechs << mech_2     

    return mechs
end

end # module Features
end # module XMPP
