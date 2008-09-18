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
    @@stanzas = {}

    attr_accessor :type, :state, :id, :xml, :stream

    TYPE_GET     = 0x00000001
    TYPE_SET     = 0x00000002

    STATE_NONE   = 0x00000000
    STATE_SET    = 0x00000001
    STATE_GET    = 0x00000002
    STATE_RESULT = 0x00000004
    STATE_ERROR  = 0x00000008

    ERR_CANCEL   = 0x00000001
    ERR_CONTINUE = 0x00000002
    ERR_MODIFY   = 0x00000004
    ERR_AUTH     = 0x00000008
    ERR_WAIT     = 0x00000010

    def initialize(id)
        # Prune out all the finished ones.
        @@stanzas.delete_if { |k, v| v.state & STATE_RESULT != 0 }
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

        iq = REXML::Element.new('iq')
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
    unless elem.attributes['xmlns'] == 'jabber:iq:roster'
        stanza.error('bad-request', IQStanza::ERR_MODIFY)
        return
    end

    stanza.state = IQStanza::STATE_RESULT

    result = REXML::Document.new

    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.id)

    query = DB::User.users[@jid].roster_to_xml
    iq << query
    result << iq

    write result
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
        resource = @jid.split('@')[0] + Stream.genid
    else
        resource = elem.elements['resource'].text + Stream.genid

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
    user.add_resource(@resource)
    @state |= Stream::STATE_BIND
    
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

    if user.resources.nil? || user.resources.empty? || @resource.nil?
        stanza.error('unexpected-request', IQStanza::ERR_WAIT)
        return
    end

    stanza.state |= IQStanza::STATE_RESULT

    result = REXML::Document.new

    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.id)

    result << iq

    write result
    
    # This only serves to let Features::list() know what to do.
    @state |= Stream::STATE_SESSION

    # Send the updated features list.
    XMPP::Features::list(self)
end

end # module Client
end # module XMPP
