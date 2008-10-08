#
# synapse: a small XMPP server
# xmpp/iq_set.rb: handles <iq type='set'/> stanzas
#
# Copyright (c) 2006-2008 Eric Will <rakaur@malkier.net>
#
# $Id$
#

# Import required Ruby modules.
require 'idn'
require 'rexml/document'

# Import required xmppd modules.
require 'xmppd/var'
require 'xmppd/xmpp'

# The XMPP namespace.
module XMPP

# The IQ namespace.
# This is meant to be a mixin to a Stream.
module IQ

# The SET namespace
# This is meant to be a mixin to a Stream.
module SET

#
# Handle an incoming <iq type='set'/> stanza.
# This further delegates as well.
#
# elem:: [REXML::Element] parsed <iq/> stanza
#
# return:: [XMPP::Client] self
# 
def handle_iq_set(elem)
    unless elem.attributes['id']
        write Stanza.error(elem, 'bad-request', 'modify')
        return self
    end

    elem.elements.each do |e|
        methname = 'set_' + e.name

        unless respond_to?(methname)
            write Stanza.error(elem, 'feature-not-implemented', 'cancel')
            return self
        else
            send(methname, elem)
        end
    end

    self
end

#
# Handle a <bind/> element within an <iq/> stanza.
# This binds the client resource.
#
# elem:: [REXML::Element] parsed <iq/> stanza
#
# return:: [XMPP::Stream] self
#
def set_bind(elem)
    stanza = elem
    elem = stanza.root.elements['bind']

    # Verify namespace.
    unless elem.attributes['xmlns'] == 'urn:ietf:params:xml:ns:xmpp-bind'
        write Stanza.error(stanza, 'service-unavailable', 'cancel')
        return self
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
        resource = @jid.split('@')[0] + Stream.genid
        resource = resource[0, 1023]
    else
        resource = elem.elements['resource'].text[0, 1023]

        unless resource
            write Stanza.error(stanza, 'bad-request', 'modify')
            return self
        end
    end

    begin
        resource = IDN::Stringprep.resourceprep(resource)
    rescue Exception
        write Stanza.error(stanza, 'bad-request', 'modify')
        return self
    end

    # Is it in use?
    user = DB::User.users[@jid]
    if user.resources and user.resources[resource]
        write Stanza.error(stanza, 'conflict', 'modify')
        return self
    end

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

    user = DB::User.users[@jid] # XXX didn't i just do this?
    @resource = XMPP::Client::Resource.new(resource, self, user)
    user.add_resource(@resource)
    @state |= Stream::STATE_BIND
    
    @logger.unknown "-> resource bound to #{resource}"
    
    # Send the updated features list.
    XMPP::Features.list(self)

    self
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
def set_session(elem)
    stanza = elem
    elem = stanza.root.elements['session']

    # Verify namespace.
    unless elem.attributes['xmlns'] == 'urn:ietf:params:xml:ns:xmpp-session'
        write Stanza.error(stanza, 'bad-request', 'modify')
        return self
    end

    # Make sure they have a resource bound.
    user = DB::User.users[@jid]

    unless user.available? or @resource
        write Stanza.error(stanza, 'unexpected-request', 'wait')
        return self
    end

    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.attributes['id'])

    write iq
    
    # This only serves to let Features::list() know what to do.
    @state |= Stream::STATE_SESSION
    
    @logger.unknown "-> session silently ignored"

    # Send the updated features list.
    XMPP::Features.list(self)

    self
end

end # module SET
end # module IQ
end # module XMPP
