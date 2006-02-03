#
# xmppd: a small XMPP server
# operator.rb: server operator configuration
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

module Configure

#
# Represents operator{} configuration data.
#
class Operator
    attr_reader :jid, :announce

    def initialize
        @jid = nil
        @announce = false
    end

    def jid=(value)
        unless value =~ /\w+\@\w+/
            raise ArgumentError, "invalid 'jid' syntax"
        end

        @jid = value
    end

    def announce=(value)
        unless value == true || value == false
            raise ArgumentError, "invalid 'announce' (must be true/false)"
        end

        @announce = value
    end
end

end # module Configure
