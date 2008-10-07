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
require 'xmppd/xmpp/resource'
require 'xmppd/xmpp/stanza'
require 'xmppd/xmpp/stream'

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

    if ns =~ /^\w+\:\w+\:(\w+)$/
        methname = 'query_' + $1

        unless respond_to?(methname)
            write Stanza.error(stanza, 'service-unavailable', 'cancel')
            return self
        end

        send(methname, stanza)
    elsif ns[0, 7] == 'http://'
        write Stanza.error(stanza, 'service-unavailable', 'cancel')
        return self
    end

    self
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

end # module GET
end # module IQ
end # module XMPP
