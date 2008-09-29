#
# xmppd: a small XMPP server
# xmpp/client_presence.rb: handles presence stanzas from clients
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id: client_iq.rb 50 2008-09-18 20:09:56Z rakaur $
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

class PresenceStanza < XMPP::Stanza
    def initialize(id = nil)
        super(id)
    end

    ######
    public
    ######

    def error(defined_condition, type)
        super('presence', defined_condition, type)
    end
end

def handle_presence(elem)
    # Is the stream open?
    unless established?
        error('unexpected-request')
        return
    end

    stanza = PresenceStanza.new(elem.attributes['id'])
    stanza.to = elem.attributes['to'] or nil
    stanza.from = elem.attributes['from'] or nil
    stanza.type = elem.attributes['type'] or nil
    stanza.state = PresenceStanza::STATE_NONE
    stanza.xml = elem
    stanza.stream = self

    elem.attributes['type'] ||= 'none'
    
    methname = 'handle_type_' + elem.attributes['type']

    unless respond_to? methname
        stanza.error('bad-request', PresenceStanza::ERR_CANCEL)
        return
    else
        send(methname, stanza)
    end
end
 
# No type signals avilability.
def handle_type_none(stanza)
    case stanza.xml.elements['show'].text
    when 'away'
        @resource.show = Resource::SHOW_AWAY
    when 'chat'
        @resource.show = Resource::SHOW_CHAT
    when 'dnd'
        @resource.show = Resource::SHOW_DND
    when 'xa'
        @resource.show = Resource::SHOW_XA
    else
        stanza.error('bad-request', PresenceStanza::ERR_MODIFY)
        return
    end if stanza.xml.elements['show']
    
    @resource.show ||= Resource::SHOW_AVAILABLE

    @logger.unknown "(#{@resource.name}) -> set availability"
    
    if stanza.xml.elements['status']
        s = stanza.xml.elements['status'].text
        @resource.status = s
        @logger.unknown "(#{@resource.name}) -> status set to '#{s}'"
    end
    
    if stanza.xml.elements['priority']
        p = stanza.xml.elements['priority'].text.to_i
        @resource.priority = p
        @logger.unknown "(#{@resource.name}) -> priority set to #{p}"
    end

    # XXX - directed presence

    # Broadcast it to relevant entities.
    @resource.broadcast_presence(stanza)

    # Was this their initial presence?
    unless @resource.available?
        @resource.state |= Resource::STATE_AVAILABLE

        # If they're sending out initial presense, then they
        # need their contacts' presence.
        @resource.send_roster_presence
    end
end

# They're logging off.
def handle_type_unavailable(stanza)
    @resource.broadcast_presence(stanza)
    @state &= ~Stream::STATE_ESTAB
end

end # module Client
end # module XMPP
