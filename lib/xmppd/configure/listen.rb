#
# xmppd: a small XMPP server
# listen.rb: port listening configuration
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

module Configure

#
# Represents a single <listen/> entry.
#
class Listen
    attr_accessor :host, :c2s, :s2s

    def initialize
        host = nil
        @c2s = []
        @s2s = []
    end
end

end # module Configure
