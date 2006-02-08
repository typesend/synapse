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
# Represents listen{} configuration data.
#
class Listen
    attr_accessor :c2s, :s2s, :certfile

    def initialize
        @c2s = []
        @s2s = []
        @certfile = nil
    end
end

end # module Configure
