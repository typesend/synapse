#
# synapse: a small XMPP server
# xmpp/stanza.rb: handles stanzas from clients
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
# The XMPP namespace.
#
module XMPP

#
# The Stanza namespace.
#
module Stanza

extend self

ERR_TYPES = ['auth', 'cancel', 'continue', 'modify', 'wait']

#
# Generate a stanza error.
#
# stanza:: [REXML::Element] the original stanza
# defined_condition:: [String] a condition defined in XMPP-CORE
# type:: [String] the type of error, must be one of:
#     - auth
#     - cancel
#     - continue
#     - modify
#     - wait
#
# return:: [REXML::Element] the stanza error
#
def error(stanza, defined_condition, type)
    unless ERR_TYPES.include?(type)
        raise ArgumentError, "type must be one of #{ERR_TYPES.join(', ')}"
    end

    stzerr = REXML::Element.new(stanza.name)
    stzerr.add_attribute('type', 'error')
    stzerr.add_attribute('id', stanza.attributes['id'])

    err = REXML::Element.new('error')
    err.add_attribute('type', type)

    cond = REXML::Element.new(defined_condition)
    cond.add_namespace('urn:ietf:params:xml:ns:xmpp-stanzas')

    err << cond
    stzerr << err

    return stzerr
end

end # module Stanza

end # module XMPP
