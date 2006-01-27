#
# xmppd: a small XMPP server
# auth.rb: client authorization configuration
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

module Configure

#
# Represents a single <auth/> entry.
#
class Auth
    attr_accessor :virtual_host, :type, :ip, :match, :plain, :legacy_auth

    def initialize
        @virtual_host = nil
        @type = nil
        @ip = []
        @match = []
        @plain = false
        @legacy_auth = false
    end
end

end # module Configure
