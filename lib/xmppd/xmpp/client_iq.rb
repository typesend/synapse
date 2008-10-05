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
    unless elem.attributes['id']
        write Stanza.error(elem, 'bad-request', 'modify')
        return
    end

    elem.elements.each do |e|
        methname = 'handle_iq_set_' + e.name

        unless respond_to? methname
            write Stanza.error(elem, 'feature-not-implemented', 'cancel')
            return
        else
            send(methname, elem)
        end
    end
end

def handle_iq_get(elem)
    unless elem.attributes['id']
        write Stanza.error(elem, 'bad-request', 'modify')
        return
    end

    elem.elements.each do |e|
        methname = 'handle_iq_get_' + e.name

        unless respond_to? methname
            write Stanza.error(elem, 'feature-not-implemented', 'cancel')
            return
        else
            send(methname, elem)
        end
    end
end

def handle_iq_get_query(elem)
    stanza = elem
    elem = stanza.root.elements['query']

    # Verify namespace.
    if elem.attributes['xmlns'] == 'jabber:iq:easter'
        write Stanza.error(stanza, '114-97-107-97-117-114', 'cancel')
        return
    elsif elem.attributes['xmlns'] != 'jabber:iq:roster'
        write Stanza.error(stanza, 'feature-not-implemented', 'modify')
        return
    end

    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.attributes['id'])

    query = DB::User.users[@jid].roster_to_xml
    iq << query

    write iq

    @resource.interested = true
    @logger.unknown "(#{@resource.name}) -> set state to interested"
end

def handle_iq_set_bind(elem)
    stanza = elem
    elem = stanza.root.elements['bind']

    # Verify namespace.
    unless elem.attributes['xmlns'] == 'urn:ietf:params:xml:ns:xmpp-bind'
        write Stanza.error(stanza, 'bad-request', 'modify')
        return
    end

    resource = nil

    #
    # If it's empty they want us to generate one for them, if not
    # they've supplied a string to use. The new draft RFC says we should
    # add random text onto that anyhow, but apparently no one likes
    # that. We'll go ahead and accept theirs if they supply it,
    # which they shouldn't.
    #
    unless elem.has_elements?
        resource = @jid.split('@')[0]
    else
        resource = elem.elements['resource'].text + Stream.gen_id

        unless resource
            write Stanza.error(stanza, 'bad-request', 'modify')
            return
        end
    end

    begin
        resource = IDN::Stringprep.resourceprep(resource)
    rescue Exception
        write Stanza.error(stanza, 'bad-request', 'modify')
        return
    end

    # Is it in use?
    user = DB::User.users[@jid]
    user.resources.each do |k, v|
        if v.name == resource
            write Stanza.error(stanza, 'conflict', 'cancel')
            return
        end
    end if user.resources

    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.attributes['id'])

    bind = REXML::Element.new('bind')
    bind.add_namespace('urn:ietf:params:xml:ns:xmpp-bind')

    jid = REXML::Element.new('jid')
    jid.text = @jid + '/' + resource

    bind << jid
    iq << bind

    write iq

    user = DB::User.users[@jid]
    @resource = Resource.new(resource, self, user)
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
def handle_iq_set_session(elem)
    stanza = elem
    elem = stanza.root.elements['session']

    # Verify namespace.
    unless elem.attributes['xmlns'] == 'urn:ietf:params:xml:ns:xmpp-session'
        write Stanza.error(stanza, 'bad-request', 'modify')
        return
    end

    # Make sure they have a resource bound.
    user = DB::User.users[@jid]

    unless user.available? or @resource
        write Stanza.error(stanza, 'unexpected-request', 'wait')
        return
    end

    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.attributes['id'])

    write iq
    
    # This only serves to let Features::list() know what to do.
    @state |= Stream::STATE_SESSION
    
    @logger.unknown "-> session silently ignored"

    # Send the updated features list.
    XMPP::Features::list(self)
end

end # module Client

end # module XMPP
