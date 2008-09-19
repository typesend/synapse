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
    attr_reader :name, :stream, :user, :priority, :status, :show, :status
    
    SHOW_AVAILABLE = 0x00000000
    SHOW_AWAY      = 0x00000001
    SHOW_CHAT      = 0x00000002
    SHOW_DND       = 0x00000004
    SHOW_XA        = 0x00000008

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

        self.priority = priority
    end
    
    ######
    public
    ######
    
    def show=(show)
        unless show.class == Fixnum
            raise ResourceError, "show must be a numeric flag"
        end
        
        @show = show
    end
    
    def status=(status)
        unless status.class == String
            raise ResourceError, "status must be a string"
        end

        @status = status[0, 1024]
    end
    
    def priority=(priority)
        if (priority < -128) or (priority > 127)
            raise ResourceError, "priority isn't within range (-128 .. 127)"
        end
        
        @priority = priority
    end
end

end # module XMPP