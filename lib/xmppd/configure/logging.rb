#
# xmppd: a small XMPP server
# logging.rb: logging configuration
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

module Configure

#
# Represents a single <logging/> entry.
#
class Logging
    attr_accessor :general, :c2s, :s2s

    def initialize
        @general = nil
        @c2s = nil
        @s2s = nil
    end
end

end # module Configure
