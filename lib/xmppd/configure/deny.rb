#
# synapse: a small XMPP server
# deny.rb: client authorization configuration
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

module Configure

#
# Represents deny{} configuration data.
#
class Deny
    attr_accessor :host, :match

    def initialize
        @host = []
        @match = []
    end
end

end # module Configure
