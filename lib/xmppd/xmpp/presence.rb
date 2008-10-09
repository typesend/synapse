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

    elem.attributes['type'] ||= 'none'
    
    methname = 'presence_' + elem.attributes['type']

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

end # module Presence
end # module XMPP
