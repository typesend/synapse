#
# synapse: a small XMPP server
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
require 'xmppd/xmpp/stanza'
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

class IQStanza < XMPP::Stanza
    TYPE_GET     = 0x00000001
    TYPE_SET     = 0x00000002

    def initialize(id)
        super(id)
    end

    ######
    public
    ######

    def error(defined_condition, type)
        super('iq', defined_condition, type)
    end
end

def handle_iq(elem)
    # Is the stream open?
    unless established?
        error('unexpected-request')
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
    stanza.stream = self

    unless elem.attributes['id']
        stanza.error('bad-request', IQStanza::ERR_MODIFY)
        return
    end

    elem.elements.each do |e|
        methname = 'handle_iq_set_' + e.name

        unless respond_to? methname
            stanza.error('feature-not-implemented', IQStanza::ERR_CANCEL)
            return
        else
            send(methname, stanza)
        end
    end
end

def handle_iq_get(elem)
    stanza = IQStanza.new(elem.attributes['id'])
    stanza.type = IQStanza::TYPE_GET
    stanza.state = IQStanza::STATE_GET
    stanza.xml = elem
    stanza.stream = self

    unless elem.attributes['id']
        stanza.error('bad-request', IQStanza::ERR_MODIFY)
        return
    end

    elem.elements.each do |e|
        methname = 'handle_iq_get_' + e.name

        unless respond_to? methname
            stanza.error('feature-not-implemented', IQStanza::ERR_CANCEL)
            return
        else
            send(methname, stanza)
        end
    end
end

def handle_iq_get_query(stanza)
    elem = stanza.xml.elements['query']

    # Verify namespace.
    if elem.attributes['xmlns'] == 'jabber:iq:easter'
        stanza.error('114-97-107-97-117-114', IQStanza::ERR_CANCEL)
        return
    elsif elem.attributes['xmlns'] != 'jabber:iq:roster'
        stanza.error('feature-not-implemented', IQStanza::ERR_MODIFY)
        return
    end

    stanza.state = IQStanza::STATE_RESULT

    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.id)

    query = DB::User.users[@jid].roster_to_xml
    iq << query

    write iq

    @resource.state |= Resource::STATE_INTERESTED
    @logger.unknown "(#{@resource.name}) -> set state to interested"
end

def handle_iq_set_bind(stanza)
    elem = stanza.xml.elements['bind']

    # Verify namespace.
    unless elem.attributes['xmlns'] == 'urn:ietf:params:xml:ns:xmpp-bind'
        stanza.error('bad-request', IQStanza::ERR_MODIFY)
        return
    end

    resource = nil

    #
    # If it's empty they want us to generate one for them, if not
    # they've supplied a string to use. The new draft RFC says we should
    # add random text onto that anyhow, so we do.
    #
    unless elem.has_elements?
        resource = @jid.split('@')[0] + rand(rand(100000)).to_s
    else
        resource = elem.elements['resource'].text + rand(rand(10000)).to_s

        unless resource
            stanza.error('bad-request', IQStanza::ERR_MODIFY)
            return
        end
    end

    begin
        resource = IDN::Stringprep.resourceprep(resource)
    rescue Exception
        stanza.error('bad-request', IQStanza::ERR_MODIFY)
        return
    end

    # Is it in use?
    user = DB::User.users[@jid]
    user.resources.each do |k, v|
        if v.name == resource
            stanza.error('conflict', IQStanza::ERR_CANCEL)
            return
        end
    end if user.resources

    stanza.state |= IQStanza::STATE_RESULT

    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.id)

    bind = REXML::Element.new('bind')
    bind.add_namespace('urn:ietf:params:xml:ns:xmpp-bind')

    jid = REXML::Element.new('jid')
    jid.text = @jid + '/' + resource

    bind << jid
    iq << bind

    write iq

    user = DB::User.users[@jid]
    @resource = Resource.new(resource, self, user, 0)
    user.add_resource(@resource)
    @state |= Stream::STATE_BIND
    
    @logger.unknown "-> resource bound to #{resource}"
    
    # Send the updated features list.
    XMPP::Features::list(self)
end

# XXX
#
# Session has been removed in the latest draft RFC.
# I'm keeping this here because none of the clients
# I tested actually bother to look for it in <features/>
# and just send the iq stanza anyway.
#
# Do the standard checks, tell them it succeeded, and
# never think about it again.
#
def handle_iq_set_session(stanza)
    elem = stanza.xml.elements['session']

    # Verify namespace.
    unless elem.attributes['xmlns'] == 'urn:ietf:params:xml:ns:xmpp-session'
        stanza.error('bad-request', IQStanza::ERR_MODIFY)
        return
    end

    # Make sure they have a resource bound.
    user = DB::User.users[@jid]

    unless user.available? or @resource
        stanza.error('unexpected-request', IQStanza::ERR_WAIT)
        return
    end

    stanza.state |= IQStanza::STATE_RESULT

    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.id)

    write iq
    
    # This only serves to let Features::list() know what to do.
    @state |= Stream::STATE_SESSION
    
    @logger.unknown "-> session silently ignored"

    # Send the updated features list.
    XMPP::Features::list(self)
end

end # module Client
end # module XMPP
