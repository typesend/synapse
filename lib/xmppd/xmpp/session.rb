#
# xmppd: a small XMPP server
# xmpp/session.rb: handles client sessions
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

def SessionError
end

class Session
    attr_reader :stream, :user

    def initialize(stream, user)
        unless stream.class == ClientStream
            raise SessionError, "stream isn't a client stream"
        end

        @stream = stream

        unless user.class == DB::User
            raise SessionError, "user isn't a db user"
        end

        @user = user
    end
end

end # module XMPP
