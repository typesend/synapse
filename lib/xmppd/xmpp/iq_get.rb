#
# synapse: a small XMPP server
# xmpp/iq_get.rb: handles <iq type='get'/> stanzas
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
module IQ

# The GET namespace.
# This is meant to be a mixin to a Stream.
module GET

#
# Handle a incoming <iq type='get'/> stanza.
# This further delegates as well.
#
# elem:: [REXML::Element] parsed <iq/> stanza
#
# return:: [XMPP::Stream] self
# 
def handle_iq_get(elem)
    unless elem.attributes['id']
        write Stanza.error(elem, 'bad-request', 'modify')
        return self
    end

    elem.elements.each do |e|
        methname = 'get_' + e.name

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
# <query/> is used for just about everything.
#
# elem:: [REXML::Element] parsed <iq/> stanza
#
# return:: [XMPP::Stream] self
#
def get_query(elem)
    stanza = elem
    elem = stanza.root.elements['query']

    # Verify namespace.
    ns = elem.attributes['xmlns']

    re1 = /^\w+\:\w+\:(\w+)$/
    re2 = /^http\:\/\/jabber\.org\/protocol\/(.*)$/

    m = re1.match(ns)
    m = re2.match(ns) unless m

    if m
        methname = 'query_' + m[1].sub('#', '_')

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

def query_disco_items(stanza)
    unless stanza.attributes['to']
        write Stanza.error(stanza, 'service-unavailable', 'modify')
        return self
    end

    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.attributes['id'])

    query = REXML::Element.new('query')
    query.add_namespace('http://jabber.org/protocol/disco#items')

    # If it's to a bare JID, we handle it.
    jid_to = stanza.attributes['to']
    if not jid_to.include?('/') and jid_to.include?('@')
        user = DB::User.users[jid_to]

        unless @resource.user.subscribed?(user)
            write Stanza.error(stanza, 'service-unavailable', 'cancel')
            return self
        end

        user.resources.each do |name, rec|
            item = REXML::Element.new('item')
            item.add_attribute('jid', rec.jid)
            query << item
        end if user.resources
    end

    iq << query

    write iq
end

FEATURES = [ 'http://jabber.org/protocol/disco#items',
             'http://jabber.org/protocol/disco#info',
             'stringprep',
             'dnssrv',
             'msgoffline',
             'urn:xmpp:delay',
             'jabber:iq:easter',
             'jabber:iq:version' ]

def query_disco_info(stanza)
    unless stanza.attributes['to']
        write Stanza.error(stanza, 'service-unavailable', 'modify')
        return self
    end

    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.attributes['id'])

    query = REXML::Element.new('query')
    query.add_namespace('http://jabber.org/protocol/disco#info')

    # If it's to a bare JID, we handle it.
    jid_to = stanza.attributes['to']
    if not jid_to.include?('/') and jid_to.include?('@')
        user = DB::User.users[jid_to]

        unless @resource.user.subscribed?(user)
            write Stanza.error(stanza, 'service-unavailable', 'cancel')
            return self
        end

        type = user.oper? ? 'admin' : 'registered'

        identity = REXML::Element.new('identity')
        identity.add_attribute('category', 'account')
        identity.add_attribute('type', type)

        query << identity
    else
        identity = REXML::Element.new('identity')
        identity.add_attribute('category', 'server')
        identity.add_attribute('type', 'im')

        query << identity

        # Now list our supported features.
        FEATURES.each do |feat|
            feature = REXML::Element.new('feature')
            feature.add_attribute('var', feat)
            query << feature
        end
    end

    iq << query

    write iq
end

def query_easter(stanza)
    write Stanza.error(stanza, '114-97-107-97-117-114', 'cancel')
    return self
end

def query_roster(stanza)
    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.attributes['id'])

    query = DB::User.users[@jid].roster_to_xml
    iq << query

    write iq

    @resource.interested = true
    @logger.unknown "(#{@resource.name}) -> set state to interested"

    self
end

# This implements XEP-0092.
def query_version(stanza)
    iq = REXML::Element.new('iq')
    iq.add_attribute('type', 'result')
    iq.add_attribute('id', stanza.attributes['id'])

    query = REXML::Element.new('query')
    query.add_namespace('jabber:iq:version')

    name = REXML::Element.new('name')
    name.text = 'xmppd'
    query << name

    version = REXML::Element.new('version')
    version.text = "synapse-#$version"
    query << version

    os = REXML::Element.new('os')
    os.text = RUBY_PLATFORM
    query << os # XXX - supposed to make this configurable 

    iq << query

    write iq
end

end # module GET
end # module IQ
end # module XMPP
