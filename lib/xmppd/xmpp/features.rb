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

    if !stream.tls
        starttls = REXML::Element.new('starttls')
        starttls.add_namespace('urn:ietf:params:xml:ns:xmpp-tls')

        unless stream.auth.plain
            starttls.add_element(REXML::Element.new('required'))
        end

        feat << starttls

        mechs = REXML::Element.new('mechanisms')
        mechs.add_namespace('urn:ietf:params:xml:ns:xmpp-sasl')

        mech_1 = REXML::Element.new('mechanism')
        mech_1.text = 'DIGEST-MD5'
        mechs << mech_1

        mech_2 = REXML::Element.new('mechanism')
        mech_2.text = 'PLAIN'
        mechs << mech_2

        feat << mechs
    else
        # Until we have SASL.
        stream.error('internal-server-error')
    end

    xml << feat
    stream.write(xml)
end

end # module Features
end # module XMPP
