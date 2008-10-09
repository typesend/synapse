#
# synapse: a small XMPP server
# xmpp/iq.rb: handles <iq/> stanzas
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

require 'xmppd/xmpp/iq_get'
require 'xmppd/xmpp/iq_set'

# The XMPP namespace.
module XMPP

# The IQ namespace.
# This is meant to be a mixin to a Stream.
module IQ

#
# Handle an incoming <iq/> stanza.
# IQ stanzas are somewhat-synchronous.
# This handler breaks down further to handle
# each type of IQ stanza (get, set, result).
#
# elem:: [REXML::Element] parsed <iq/> stanza
#
# return:: [XMPP::Stream] self
#
def handle_iq(elem)
    # Are we ready for <iq/> stanzas?
    unless iq_ready?
        error('unexpected-request')
        return self
    end

    elem.attributes['from'] ||= @resource.jid if @resource
    to_jid = elem.attributes['to']

    # This is kind of complicated.
    # If the target is nil, it's to us.
    # If the target has an '@' in it, it's to a user, maybe ours.
    # Otherwise, the target is a domain. Maybe us.
    case to_jid
    when nil
        # When there is no 'to', it's to us.
        handle_local_iq(elem)
    when /\@/
        # If it's a bare/full JID, it's for routing.
        @resource.send_iq(elem)
    else
        if $config.hosts.include?(to_jid)
            handle_local_iq(elem)
        else
            write Stanza.error(elem, 'feature-not-implemented', 'cancel')
        end
    end

    self
end

def handle_local_iq(elem)
    handle_iq_set(elem) if elem.attributes['type'] == 'set'
    handle_iq_get(elem) if elem.attributes['type'] == 'get'
    handle_iq_result(elem) if elem.attributes['type'] == 'result'
end

def handle_iq_result(stanza)
end

include XMPP::IQ::GET # Handles <iq type='get'/> stanzas.
include XMPP::IQ::SET # Handles <iq type='set'/> stanzas.

end # module IQ
end # module XMPP
