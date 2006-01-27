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
# Represents a single <operator/> entry.
#
class Operator
    attr_accessor :virtual_host, :jids, :announce

    def initialize
        @virtual_host = nil
        @jid = []
        @announce = false
    end
end

end # module Configure
