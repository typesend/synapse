#
# synapse: a small XMPP server
# xmpp/message.rb: handles <message/> stanzas
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
# The Message namespace.
# This is meant to be a mixin to a Stream.
#
module Message

extend self

def handle_message(elem)
    # Is the stream open?
    unless established?
        error('unexpected-request')
        return
    end

    elem.attributes['type'] ||= 'normal'
    elem.attributes['from'] ||= @resource.jid

    to_jid = elem.attributes['to']

    unless to_jid
        write Stanza.error(elem, 'bad-request', 'cancel')
    end

    # Separate out the JID parts.
    node,   domain   = to_jid.split('@')
    domain, resource = domain.split('/')

    # Check to see if it's to a remote user.
    unless $config.hosts.include?(domain)
        write Stanza.error(elem, 'feature-not-implemented', 'cancel')
        return
    end

    # Must be to a local user.
    user = DB::User.users[node + '@' + domain]

    unless user
        write Stanza.error(elem, 'service-unavailable', 'cancel')
        return
    end

    # Are they online?
    # XXX - this gets stored plain in the db... maybe zlib it?
    unless user.available?
        # This implements XEP-0203.
        datetime = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
        delay = REXML::Element.new('delay')
        delay.add_attribute('stamp', datetime)
        delay.add_attribute('from', @myhost)
        delay.add_namespace('urn:xmpp:delay')
        delay.text = 'Offline Storage'

        elem << delay
        user.offline_stanzas['message'] << elem.to_s

        return
    end

    # If it's to a specific resource, try to find it.
    if resource and user.resources[resource]
        to_stream = user.resources[resource].stream
    else
        to_stream = user.front_resource.stream
        # XXX - rewrite the to?
    end

    # And deliver!
    to_stream.write elem
end
 
end # module Message
end # module XMPP
