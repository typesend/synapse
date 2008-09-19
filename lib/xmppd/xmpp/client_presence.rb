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

# XXX - need to abstract out a base Stanza class eventually
class PresenceStanza
    @@stanzas = {} # XXX - not sure if this is necessary

    attr_accessor :to, :from, :state, :id, :xml, :stream

    STATE_NONE   = 0x00000000
    STATE_DONE   = 0x00000004
    STATE_ERROR  = 0x00000008

    ERR_CANCEL   = 0x00000001
    ERR_CONTINUE = 0x00000002
    ERR_MODIFY   = 0x00000004
    ERR_AUTH     = 0x00000008
    ERR_WAIT     = 0x00000010

    def initialize(id)
        # Prune out all the finished ones.
        @@stanzas.delete_if { |k, v| v.state & STATE_DONE != 0 }
        @@stanzas.delete_if { |k, v| v.state & STATE_ERROR != 0 }

        @@stanzas[id] = self
        @id = id
    end

    ######
    public
    ######

    def error(defined_condition, type)
        @state = STATE_ERROR

        result = REXML::Document.new

        iq = REXML::Element.new('presence')
        iq.add_attribute('from', @to) if @to
        iq.add_attribute('to', @from) if @from
        iq.add_attribute('type', 'error')
        iq.add_attribute('id', @id)

        iq << @xml.elements[1]

        err = REXML::Element.new('error')

        case type
        when ERR_CANCEL
            err.add_attribute('type', 'cancel')
        when ERR_CONTINUE
            err.add_attribute('type', 'continue')
        when ERR_MODIFY
            err.add_attribute('type', 'modify')
        when ERR_AUTH
            err.add_attribute('type', 'auth')
        when ERR_WAIT
            err.add_attribute('type', 'wait')
        end

        cond = REXML::Element.new(defined_condition)
        cond.add_namespace('urn:ietf:params:xml:ns:xmpp-stanzas')

        err << cond
        iq << err
        result << iq

        @stream.write iq
    end
end

def handle_presence(elem)
    # Is the stream open?
    if Stream::STATE_ESTAB & @state == 0
        error('unexpected-request')
        return
    end

    stanza = PresenceStanza.new(elem.attributes['id'])
    stanza.to = elem.attributes['to'] or nil
    stanza.from = elem.attributes['from'] or nil
    stanza.state = IQStanza::STATE_NONE
    stanza.xml = elem
    stanza.stream = self

    unless elem.attributes['id']
        stanza.error('bad-request', PresenceStanza::ERR_MODIFY)
        return
    end
    
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
    # XXX - broadcast...
    
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
    
    @logger.unknown '-> set availability'
    
    if stanza.xml.elements['status']
        s = stanza.xml.elements['status'].text
        @resource.status = s
        @logger.unknown "-> status set to '#{s}'"
    end
    
    if stanza.xml.elements['priority']
        p = stanza.xml.elements['priority'].text.to_i
        @resource.priority = p
        @logger.unknown "-> priority set to #{p}"
    end

    stanza.state = PresenceStanza::STATE_DONE
end

# They're logging off.
def handle_type_unavailable
    # XXX - broadcast...
    # they send the closing stream.
    # we probably want to do this in Stream#close if they're Stream::STATE_ESTAB
end

end # module Client
end # module XMPP
