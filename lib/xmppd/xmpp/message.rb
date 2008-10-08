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

    # To must be present and it must not be just a domain.
    unless to_jid and to_jid.include?('@')
        write Stanza.error(elem, 'bad-request', 'cancel')
        return self
    end

    @resource.send_message(elem)
end
 
end # module Message
end # module XMPP
