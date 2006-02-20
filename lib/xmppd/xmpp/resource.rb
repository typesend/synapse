#
# xmppd: a small XMPP server
# xmpp/resource.rb: handles client resources
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#

#
# Import required xmppd modules.
#
require 'xmppd/db'

require 'xmppd/xmpp/stream'

#
# The XMPP namespace.
#
module XMPP

class ResourceError
end

class Resource
    attr_reader :name, :stream, :user, :priority

    def initialize(name, stream, user, priority = 0)
        @name = name

        unless stream.class == ClientStream
            raise ResourceError, "stream isn't a client stream"
        end

        @stream = stream

        unless user.class == DB::User
            raise ResourceError, "user isn't a db user"
        end

        @user = user

        if priority < -128 || priority > 127
            raise ResourceError, "priority isn't within range (-128 - 127)"
        end

        @priority = priority
    end
end

end # module XMPP
