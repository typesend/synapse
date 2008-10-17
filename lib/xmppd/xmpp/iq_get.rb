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
        methname = 'gquery_' + m[1].sub('#', '_')

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

# XXX - hack
# This is so Adium doesn't die.
# Make sure to report this.
def gquery_auth(stanza)
    # If adium never gets a response, it's okay.
end

def gquery_disco_items(stanza)
    unless stanza.attributes['to']
        write Stanza.error(stanza, 'service-unavailable', 'modify')
        return self
    end

    iq    = Stanza.new_iq('result', stanza.attributes['id'])
    query = Stanza.new_query('http://jabber.org/protocol/disco#items')

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
             'vcard-temp',
             'urn:xmpp:delay',
             'jabber:iq:easter',
             'jabber:iq:version' ]

def gquery_disco_info(stanza)
    unless stanza.attributes['to']
        write Stanza.error(stanza, 'service-unavailable', 'modify')
        return self
    end

    iq    = Stanza.new_iq('result', stanza.attributes['id'])
    query = Stanza.new_query('http://jabber.org/protocol/disco#info')

    # If it's to a bare JID, we handle it.
    jid_to = stanza.attributes['to']
    if not jid_to.include?('/') and jid_to.include?('@')
        user = DB::User.users[jid_to]

        unless @resource.user.subscribed?(user)
            write Stanza.error(stanza, 'service-unavailable', 'cancel')
            return self
        end

        type = user.operator? ? 'admin' : 'registered'

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

def gquery_easter(stanza)
    write Stanza.error(stanza, '114-97-107-97-117-114', 'cancel')
    return self
end

# This implements XEP-0077.
def gquery_register(stanza)
    iq    = Stanza.new_iq(result, stanza.attributes['id'])
    query = Stanza.new_query('jabber:iq:register')

    if sasl?
        user = DB::User.users[@jid]

        registered = REXML::Element.new('registered')
        username   = REXML::Element.new('username')
        password   = REXML::Element.new('password')

        username.text = user.node
        password.text = [DIGEST-MD5]

        query << registered
        query << username
        query << password

        iq << query

        write iq

        return self
    end

    instructions = REXML::Element.new('instructions')
    instructions.text = 'Choose a username and password for use with ' +
                        "this service.\n"

    username = REXML::Element.new('username')
    password = REXML::Element.new('password')

    query << instructions
    query << username
    query << password

    iq << query

    write iq

    return self
end
 
def gquery_roster(stanza)
    iq    = Stanza.new_iq('result', stanza.attributes['id'])
    query = DB::User.users[@jid].roster_to_xml
    iq    << query

    write iq

    @resource.interested = true
    @logger.unknown "(#{@resource.name}) -> set state to interested"

    self
end

# This implements XEP-0092.
def gquery_version(stanza)
    iq    = Stanza.new_iq('result', stanza.attributes['id'])
    query = Stanza.new_query('jabber:iq:version')

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

# This implements XEP-0054.
def get_vCard(elem)
    stanza = elem
    elem = stanza.root.elements['vCard']

    # Verify the namespace.
    unless elem.attributes['xmlns'] == 'vcard-temp'
        write Stanza.error(stanza, 'bad-request', 'modify')
        return self
    end

    # Separate out the JID parts.
    jid              = stanza.attributes['to']
    jid            ||= @resource.jid
    node,   domain   = jid.split('@')
    domain, resource = domain.split('/')

    vcard = @resource.user.vcard

    unless jid == @resource.jid
        # Must be to a local user.
        user = DB::User.users[node + '@' + domain]

        unless user and @resource.user.subscribed?(user)
            write Stanza.error(stanza, 'service-unavailable', 'cancel')
            return
        end

        vcard = user.vcard
    end

    if not vcard or vcard.empty?
        #write Stanza.error(stanza, 'item-not-found', 'cancel')
        #return self

        write %{<iq type='result' id='#{stanza.attributes['id']}' } +
              %{from='#{jid}'><vCard xmlns='vcard-temp'/></iq>} 

        return self
    end

    # I need to build this myself. Just suffice it to say REXML blows.
    write %{<iq type='result' id='#{stanza.attributes['id']}' } +
          %{from='#{jid}'>#{vcard}</iq>}
end

end # module GET
end # module IQ
end # module XMPP
