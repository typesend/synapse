#
# synapse: a small XMPP server
# xmpp/client_presence.rb: handles presence stanzas from clients
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

def handle_presence(elem)
    # Is the stream open?
    unless established?
        error('unexpected-request')
        return
    end

    elem.attributes['type'] ||= 'none'
    
    methname = 'handle_type_' + elem.attributes['type']

    unless respond_to? methname
        write Stanza.error(elem, 'bad-request', 'cancel')
        return
    else
        send(methname, elem)
    end
end
 
# No type signals avilability.
def handle_type_none(elem)
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
    end
end

# They're logging off.
def handle_type_unavailable(elem)
    if elem.attributes['to']
        @resource.send_directed_presence(elem.attributes['to'], elem)
        return
    end

    @resource.dp_to.uniq.each do |jid|
        @resource.send_directed_presence(jid, elem)
    end

    @resource.broadcast_presence(elem)
end

end # module Client

end # module XMPP
