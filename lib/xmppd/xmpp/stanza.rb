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

class Stanza
    attr_accessor :from, :id, :state, :stream, :to, :type, :xml

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

    def initialize(id = nil)
        @id = id
    end

    ######
    public
    ######

    def error(stanza, defined_condition, type)
        @state = STATE_ERROR

        result = REXML::Document.new

        stzerr = REXML::Element.new(stanza)
        stzerr.add_attribute('type', 'error')
        stzerr.add_attribute('id', @id)

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
        stzerr << err
        result << stzerr

        @stream.write stzerr
    end
end

end # module XMPP
