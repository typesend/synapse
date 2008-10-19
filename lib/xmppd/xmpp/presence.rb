#
# synapse: a small XMPP server
# xmpp/presence.rb: handles <presence/> stanzas
#
# Copyright (c) 2006-2008 Eric Will <rakaur@malkier.net>
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
require 'xmppd/xmpp'

#
# The XMPP namespace.
#
module XMPP

#
# The Presence namespace.
# This is meant to be a mixin to a Stream.
#
module Presence

extend self

def handle_presence(elem)
    # Are we ready for <presence/> stanzas?
    unless presence_ready?
        error('unexpected-request')
        return
    end

    methname = 'presence_' + (elem.attributes['type'] or 'none')

    unless respond_to?(methname)
        write Stanza.error(elem, 'bad-request', 'cancel')
        return
    else
        send(methname, elem)
    end
end
 
# No type signals avilability.
def presence_none(elem)
    if elem.attributes['to']
        @resource.send_directed_presence(elem.attributes['to'], elem)
        return
    end

    @resource.presence_stanza = elem

    # Broadcast it to relevant entities.
    @resource.broadcast_presence(elem)

    # Was this their initial presence?
    unless @resource.available?
        @resource.available = true

        # If they're sending out initial presense, then they
        # need their contacts' presence.
        @resource.send_roster_presence

        # Do they have any offline stazas?
        return unless elem.elements['priority']
        return if elem.elements['priority'].text.to_i < 0

        # XXX - only deliver messages for now
        @resource.user.offline_stanzas.each do |kind, stanzas|
            stanzas.each { |stanza| write stanza } if kind == 'message'
            @resource.user.offline_stanzas[kind] = []
        end
    end
end

# They're logging off.
def presence_unavailable(elem)
    if elem.attributes['to']
        @resource.send_directed_presence(elem.attributes['to'], elem)
        return
    end

    @resource.presence_stanza = elem

    @resource.dp_to.uniq.each do |jid|
        @resource.send_directed_presence(jid, elem)
    end

    @resource.broadcast_presence(elem)
end

def presence_subscribe(elem)
    if not elem.attributes['to'] or elem.attributes['to'].include?('/')
        write Stanza.error(elem, 'bad-request', 'modify')
        return
    end

    unless $config.hosts.include?(elem.attributes['to'].split('@')[1])
        write Stanza.error(elem, 'feature-not-implented', 'cancel')
        return
    end

    suser = DB::User.users[elem.attributes['to']]

    unless suser
        write Stanza.error(elem, 'item-not-found', 'cancel')
        return
    end

    # Update our roster entry.
    myc = @resource.user.roster[suser.jid]
    route = true

    if not myc
        myc = DB::LocalContact.new(suser)
        myc.pending_out = true
        @resource.user.add_contact(myc)
    else
        if myc.subscription == 'none'
            if myc.pending_none? 
                myc.pending_out = true
            elsif myc.pending_out? and myc.pending_in?
                # No state change.
            elsif myc.pending_out?
                # No state change.
            elsif myc.pending_in?
                myc.pending_out = true
            end
        elsif myc.subscription == 'to'
            if myc.pending_none?
                # No state change.
            elsif myc.pending_in?
                # No state change.
            end
        elsif myc.subscription == 'from'
            if myc.pending_none?
                myc.pending_out = true
            elsif myc.pending_out?
                # No state change.
            end
        elsif myc.subscription == 'both'
            # No state change.
        end
    end

    # XXX - route

    # Update their roster entry.
    myc = suser.roster[@resource.user.jid]
    deliver = true

    if not myc
        myc = DB::LocalContact.new(@resource.user)
        myc.pending_in = true
        suser.add_contact(myc)
    else
        if myc.subscription == 'none'
            if myc.pending_none?
                myc.pending_in = true
            elsif myc.pending_out? and myc.pending_in?
                # No state change.
                deliver = false
            elsif myc.pending_out?
                myc.pending_in = true
            elsif myc.pending_in?
                # No state change.
                deliver = false
            end
        elsif myc.subscription == 'to'
            if myc.pending_none?
                myc.pending_in = true
            elsif myc.pending_in?
                # No state change.
                deliver = false
            end
        elsif myc.subscription == 'from'
            # XXX - auto reply 'subscribed'
            if myc.pending_none?
                # No state change.
                deliver = false
            elsif myc.pending_out?
                # No state change.
                deliver = false
            end
        elsif myc.subscription == 'both'
            # XXX - auto reply 'subscribed'
            # No state change.
            deliver = false
        end
    end

    if deliver
        @resource.user.roster[elem.attributes['to']].stime = $time
        elem.add_attribute('from', @resource.user.jid)
        @resource.send_directed_presence(elem.attributes['to'], elem)
        @resource.dp_to.delete_if { |to| to =~ /#{elem.attributes['to']}/ }

        # Roster push to all of our resources.
        iq    = Stanza.new_iq('set')
        query = Stanza.new_query('jabber:iq:roster')

        query << @resource.user.roster[suser.jid].to_xml
        iq    << query

        @resource.user.resources.each do |n, rec|
            next unless rec.interested?
            rec.stream.write iq
        end
    end
end

def presence_unsubscribe(elem)
    if not elem.attributes['to'] or elem.attributes['to'].include?('/')
        write Stanza.error(elem, 'bad-request', 'modify')
        return
    end

    unless $config.hosts.include?(elem.attributes['to'].split('@')[1])
        write Stanza.error(elem, 'feature-not-implented', 'cancel')
        return
    end

    suser = DB::User.users[elem.attributes['to']]

    unless suser
        write Stanza.error(elem, 'item-not-found', 'cancel')
        return
    end

    # Update our roster entry.
    myc = @resource.user.roster[suser.jid]
    route = true

#    if not myc
end

def presence_subscribed(elem)
    if not elem.attributes['to'] or elem.attributes['to'].include?('/')
        write Stanza.error(elem, 'bad-request', 'modify')
        return
    end

    unless $config.hosts.include?(elem.attributes['to'].split('@')[1])
        write Stanza.error(elem, 'feature-not-implented', 'cancel')
        return
    end

    suser = DB::User.users[elem.attributes['to']]

    unless suser
        write Stanza.error(elem, 'item-not-found', 'cancel')
        return
    end

    # Update our roster entry.
    myc = @resource.user.roster[suser.jid]
    route = true

    if not myc
        # No state change.
        route = false
    elsif myc.subscription == 'none'
        if myc.pending_none?
            # No state change.
            route = false
        elsif myc.pending_out? and myc.pending_in?
            myc.subscription = 'from'
            myc.pending_in = false
        elsif myc.pending_out?
            # No state change.
            route = false
        elsif myc.pending_in?
            myc.subscription = 'from'
            myc.pending_none = true
        end
    elsif myc.subscription == 'to'
        if myc.pending_none?
            # No state change.
            route = false
        elsif myc.pending_in?
            myc.subscription = 'both'
            myc.pending_none = true
        end
    elsif myc.subscription == 'from'
        if myc.pending_none?
            # No state change.
            route = false
        elsif myc.pending_out?
            # No state change.
            route = false
        end
    elsif myc.subscription == 'both'
        # No state change.
        route = false
    end

    # Update their roster entry.
    myc = suser.roster[@resource.user.jid]

    if not myc
        # No state change.
    elsif myc.subscription == 'none'
        if myc.pending_none?
            # No state change.
        elsif myc.pending_out? and myc.pending_in?
            myc.subscription = 'to'
            myc.pending_out = false
        elsif myc.pending_out?
            myc.subscription = 'to'
            myc.pending_none = true
        elsif myc.pending_in?
            # No state change.
        end
    elsif myc.subscription == 'to'
        if myc.pending_none?
            # No state change.
        elsif myc.pending_in?
            # No state change.
        end
    elsif myc.subscription == 'from'
        if myc.pending_none?
            # No state change.
        elsif myc.pending_out?
            myc.subscription = 'both'
            myc.pending_none = true
        end
    elsif myc.subscription == 'both'
        # No state change.
    end

    # Only do the below if we route.
    return unless route

    elem.add_attribute('from', @resource.user.jid)
    @resource.send_directed_presence(elem.attributes['to'], elem)
    @resource.dp_to.delete_if { |to| to =~ /#{elem.attributes['to']}/ }

    # Roster push to all of our resources.
    iq    = Stanza.new_iq('set')
    query = Stanza.new_query('jabber:iq:roster')

    query << @resource.user.roster[suser.jid].to_xml
    iq    << query

    @resource.user.resources.each do |n, rec|
        next unless rec.interested?

        rec.stream.write iq
    end

    # Send our presence to them.
    suser.resources.each do |n, rec|
        next unless rec.available?
        @resource.send_presence(rec)
    end
end

def presence_unsubscribed(elem)
    if not elem.attributes['to'] or elem.attributes['to'].include?('/')
        write Stanza.error(elem, 'bad-request', 'modify')
        return
    end

    unless $config.hosts.include?(elem.attributes['to'].split('@')[1])
        write Stanza.error(elem, 'feature-not-implented', 'cancel')
        return
    end

    suser = DB::User.users[elem.attributes['to']]

    unless suser
        write Stanza.error(elem, 'item-not-found', 'cancel')
        return
    end

    # Update our roster entry.
    myc = @resource.user.roster[suser.jid]
    route = true

#    if not myc
end


end # module Presence
end # module XMPP
