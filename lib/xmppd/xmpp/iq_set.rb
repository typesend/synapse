#
# synapse: a small XMPP server
# xmpp/iq_set.rb: handles <iq type='set'/> stanzas
#
# Copyright (c) 2006-2008 Eric Will <rakaur@malkier.net>
#
# $Id: iq_set.rb 90 2008-10-19 04:46:48Z rakaur $
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
# Handle a <query/> element within an <iq/> stanza.
#
# elem:: [REXML::Element] parsed <iq/> stanza
#
# return:: [XMPP::Stream] self
#
def set_query(elem)
    stanza = elem
    elem = stanza.root.elements['query']

    # Verify namespace.
    ns = elem.attributes['xmlns']

    re1 = /^\w+\:\w+\:(\w+)$/
    re2 = /^http\:\/\/jabber\.org\/protocol\/(.*)$/

    m = re1.match(ns)
    m = re2.match(ns) unless m

    if m
        methname = 'squery_' + m[1].sub('#', '_')

        unless respond_to?(methname)
            write Stanza.error(stanza, 'service-unavailable', 'cancel')
            return self
        end

        send(methname, stanza)
    else
        write Stanza.error(stanza, 'service-unavailable', 'cancel')
        return self
    end

    self
end

# This implements XEP-0077.
def squery_register(stanza)
    if stanza.elements['query'].elements['remove']
        unless sasl?
            write Stanza.error(stanza, 'forbidden', 'cancel')
            return self
        end

        write Stanza.new_iq('result', stanza.attributes['id'])

        DB::User.delete(@jid)

        return self
    end

    username = stanza.elements['query'].elements['username'].text
    password = stanza.elements['query'].elements['password'].text

    if @registered and not sasl?
        write Stanza.error(stanza, 'not-acceptable', 'cancel')
        return self
    end

    unless username and password
        write Stanza.error(stanza, 'not-acceptable', 'modify')
        return self
    end

    if username.length > 1023 or password.length > 1023
        write Stanza.error(stanza, 'not-acceptable', 'modify')
        return self
    end

    user = nil

    # Password change?
    if sasl?
        user = DB::User.users[username + '@' + @myhost]
        user.password = password
    else
        # Check to see if the username is in use.
        if DB::User.users[username + '@' + @myhost]
            write Stanza.error(stanza, 'conflict', 'cancel')
            return self
        end

        # DB::User does the IDN stuff.
        @registered = true
        user = DB::User.new(username, @myhost, password)
    end

    iq = Stanza.new_iq('result', stanza.attributes['id'])

    query = Stanza.new_query('jabber:iq:register')

    un = REXML::Element.new('username')
    pw = REXML::Element.new('password')

    un.text = user.node
    pw.text = password

    query << un
    query << pw

    iq << query

    write iq
end

def squery_roster(stanza)
    item = stanza.elements['query'].elements['item']

    unless item and item.attributes['jid']
        write Stanza.error(stanza, 'bad-request', 'modify')
        return self
    end

    if item.attributes['jid'].include?('/')
        write Stanza.error(stanza, 'bad-request', 'modify')
        return self
    end

    # Separate out the JID parts.
    jid          = item.attributes['jid']
    node, domain = jid.split('@')

    # Apparently they can't add themselves. Lame.
    if jid == @resource.user.jid
        write Stanza.error(stanza, 'not-allowed', 'cancel')
        return
    end

    # Check to see if it's to a remote user.
    unless $config.hosts.include?(domain)
        write Stanza.error(stanza, 'feature-not-implemented', 'cancel')
        return
    end

    # Must be to a local user.
    user = DB::User.users[jid]

    unless user
        write Stanza.error(stanza, 'item-not-found', 'cancel')
        return
    end

    contact = @resource.user.roster[jid]

    if item.attributes['subscription'] == 'remove'
        unless contact
            write Stanza.error(stanza, 'item-not-found', 'modify')
            return self
        end

        write Stanza.new_iq('result', stanza.attributes['id'])
@logger.unknown "%s is removing %s from roster" % \
                [@resource.user.jid, user.jid]

        stanza.add_attribute('id', 'push' + rand(1000000).to_s)
        stanza.delete_attribute('from')

        @resource.user.resources.each do |n, rec|
            next unless rec.interested?
            rec.stream.write stanza
        end

        # Subscription stuff?
        if @resource.user.subscribed?(user)
@logger.unknown "%s is subscribed to %s, sending unsub" % \
                [@resource.user.jid, user.jid]

            presence = REXML::Element.new('presence')
            presence.add_attribute('type', 'unsubscribe')
            presence.add_attribute('to', jid)
            presence.add_attribute('from', @resource.user.jid)

            process_stanza(presence)
            #presence_unsubscribe(presence)
        end

        if user.subscribed?(@resource.user)
@logger.unknown "%s is subscribed to %s, sending unsub'd" % \
                [user.jid, @resource.user.jid]

            presence = REXML::Element.new('presence')
            presence.add_attribute('type', 'unsubscribed')
            presence.add_attribute('to', jid)
            presence.add_attribute('from', @resource.user.jid)

            process_stanza(presence)
            #presence_unsubscribed(presence)
        end

        return self
    end

    unless contact
        contact = DB::LocalContact.new(user)
        @resource.user.add_contact(contact)
    end

    contact.name   = item.attributes['name'] ? item.attributes['name'] : nil
    contact.groups = item.elements.collect do |e|
                         if e.name == 'group'
                             IDN::Stringprep.resourceprep(e.text[0, 1023])
                         end
                     end

    write Stanza.new_iq('result', stanza.attributes['id'])

    # Now roster push it out.
    iq    = Stanza.new_iq('set')
    query = Stanza.new_query('jabber:iq:roster')
    query << contact.to_xml
    iq    << query

    @resource.user.resources.each do |n, rec|
        next unless rec.interested?
        rec.stream.write iq
    end
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

    # Do they have too many connected already?
    recs = DB::User.users[@jid].resources
    if recs and recs.length > 10
        write Stanza.error(stanza, 'resource-constraint', 'cancel')
        return self
    end

    # Does this stream already have a resource?
    # We currently do not support multiple bindings.
    unless @resource.nil?
        write Stanza.error(stanza, 'not-allowed', 'cancel')
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

    iq = Stanza.new_iq('result', stanza.attributes['id'])

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

    write Stanza.new_iq('result', stanza.attributes['id'])
    
    # This only serves to let Features::list() know what to do.
    @state |= Stream::STATE_SESSION
    
    @logger.unknown "-> session silently ignored"

    # Send the updated features list.
    XMPP::Features.list(self)

    self
end

def set_vCard(elem)
    stanza = elem
    elem = stanza.root.elements['vCard']

    # Verify namespace.
    unless elem.attributes['xmlns'] == 'vcard-temp'
        write Stanza.error(stanza, 'bad-request', 'modify')
        return self
    end

    jid   = stanza.attributes['to']
    jid ||= @resource.jid

    unless jid == @resource.jid
        write Stanza.error(stanza, 'not-allowed', 'cancel')
        return self
    end

    @resource.user.vcard = elem.to_s

    write Stanza.new_iq('result', stanza.attributes['id'])

    self
end

end # module SET
end # module IQ
end # module XMPP
