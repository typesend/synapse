#
# xmppd: a small XMPP server
# xmpp/client_iq.rb: handles iq stanzas from clients
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'idn'
require 'rexml/document'

#
# Import required xmppd modules.
#
require 'xmppd/var'

require 'xmppd/xmpp/resource'
require 'xmppd/xmpp/session'
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

class IQStanza
    TYPE_GET     = 0x00000001
    TYPE_SET     = 0x00000002

    STATE_NONE   = 0x00000000
    STATE_SET    = 0x00000001
    STATE_GET    = 0x00000002
    STATE_RESULT = 0x00000004

    @@stanzas = {}

    attr_accessor :type, :state, :id, :xml

    def initialize(id)
        # Prune out all the finished ones.
        @@stanzas.delete_if { |k, v| v.state & STATE_RESULT != 0 }

        @@stanzas[id] = self
        @id = id
    end
end

def handle_iq(elem)
    # Is the stream open?
    if Stream::STATE_ESTAB & @state == 0
        error('invalid-namespace')
        return
    end

    handle_iq_set(elem) if elem.attributes['type'] == 'set'
    handle_iq_get(elem) if elem.attributes['type'] == 'get'
    handle_iq_result(elem) if elem.attributes['type'] == 'result'
end

def handle_iq_set(elem)
    stanza = IQStanza.new(elem.attributes['id'])
    stanza.type = IQStanza::TYPE_SET
    stanza.state = IQStanza::STATE_SET
    stanza.xml = elem

    unless elem.attributes['id']
        error('xml-not-well-formed')
        return
    end

    elem.elements.each do |e|
        methname = 'handle_iq_set_' + e.name

        unless respond_to? methname
            error('xml-not-well-formed')
            return
        else
            send(methname, stanza)
        end
    end
end

def handle_iq_get(elem)
    error('internal-server-error')
end

def handle_iq_set_bind(stanza)
    elem = stanza.xml.elements['bind']

    # Verify namespace.
    unless elem.attributes['xmlns'] == 'urn:ietf:params:xml:ns:xmpp-bind'
        error('invalid-namespace')
        return
    end

    resource = nil

    # They want us to generate one for them.
    unless elem.has_elements?
        resource = @jid.split('@')[0] + rand(rand(1000000)).to_s
    else
        resource = elem.elements['resource'].text

        unless resource
            # XXX - iq_error()
            error('xml-not-well-formed')
            return
        end
    end

    begin
        resource = IDN::Stringprep.resourceprep(resource)
    rescue Exception
        error('xml-not-well-formed')
        return
    end

    stanza.state |= IQStanza::STATE_RESULT

    result = REXML::Document.new

    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.id)

    bind = REXML::Element.new('bind')
    bind.add_namespace('urn:ietf:params:xml:ns:xmpp-bind')

    jid = REXML::Element.new('jid')
    jid.text = @jid + '/' + resource

    bind << jid
    iq << bind
    result << iq

    write result

    user = DB::User.users[@jid]
    @resource = Resource.new(resource, self, user, 0)
    @resource.state |= Resource::STATE_CONNECT
    @state |= Stream::STATE_BIND
end

def handle_iq_set_session(stanza)
    elem = stanza.xml.elements['session']

    # Verify namespace.
    unless elem.attributes['xmlns'] == 'urn:ietf:params:xml:ns:xmpp-session'
        error('invalid-namespace') # XXX - iq_error
        return
    end

    stanza.state |= IQStanza::STATE_RESULT

    result = REXML::Document.new

    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.id)

    result << iq

    write result

    user = DB::User.users[@jid]
    @session = Session.new(self, user)
    @resource.state |= Resource::STATE_ACTIVE
    @state |= Stream::STATE_SESSION
end

end # module Client
end # module XMPP
