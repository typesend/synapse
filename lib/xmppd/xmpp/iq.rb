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
    # Is the stream open?
    unless established?
        error('unexpected-request')
        return self
    end

    handle_iq_set(elem) if elem.attributes['type'] == 'set'
    handle_iq_get(elem) if elem.attributes['type'] == 'get'
    handle_iq_result(elem) if elem.attributes['type'] == 'result'

    self
end

include XMPP::IQ::GET # Handles <iq type='get'/> stanzas.
include XMPP::IQ::SET # Handles <iq type='set'/> stanzas.

end # module IQ
end # module XMPP
