#
# synapse: a small XMPP server
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
    attr_accessor :state
    attr_reader :name, :stream, :user, :priority, :show, :status, :dp_to
    
    SHOW_AVAILABLE   = 0x00000000
    SHOW_AWAY        = 0x00000001
    SHOW_CHAT        = 0x00000002
    SHOW_DND         = 0x00000004
    SHOW_XA          = 0x00000008

    STATE_NONE       = 0x00000000
    STATE_AVAILABLE  = 0x00000001 # Get presence updates
    STATE_INTERESTED = 0x00000002 # Get roster pushes

    def initialize(name, stream, user, priority = 0)
        @name = name
        @state = STATE_NONE
        @status = nil
        @show = nil
        @dp_to = [] # An array of JIDs that we've sent directed presence to.

        unless stream.class == ClientStream
            raise ResourceError, "stream isn't a client stream"
        end

        @stream = stream

        unless user.class == DB::User
            raise ResourceError, "user isn't a db user"
        end

        @user = user
        @user.add_resource(self)

        self.priority = priority

        @xml = nil
    end
    
    ######
    public
    ######

    def jid
        @user.jid + '/' + @name
    end
    
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

    def available?
        return true if STATE_AVAILABLE & @state != 0
        return false
    end

    def interested?
        return true if STATE_INTERESTED & @state != 0
        return false
    end

    # Send directed presence to one JID.
    def send_directed_presence(jid, stanza)
        unless stanza.class == XMPP::Client::PresenceStanza
            raise ArgumentError, "stanza must be PresenceStanza"
        end

        node, domain = jid.split('@')
        domain, resource = domain.split('/')

        # Check to see if its to one of ours.
        user = DB::User.users[node + '@' + domain]

        if user and not user.resources.empty?
            sb = user.subscribed?(@user)

            if resource and user.resources[resource]
                send_presence(user.resources[resource], stanza)

                @dp_to << user.resources[resource].jid unless sb
                return
            end

            user.resources.each do |n, resource|
                send_presence(resource, stanza)
                @dp_to << resource.jid unless sb
            end
        end

        # XXX - If we get here then they're remote.
    end

    # Send our presence to one Resource.
    def send_presence(resource, stanza = nil)
        unless resource.class == Resource
            raise ArgumentError, "resource must be a Resource class"
        end

        unless stanza.class == XMPP::Client::PresenceStanza
            raise ArgumentError, "stanza must be PresenceStanza"
        end if stanza

        if stanza
            pre = REXML::Element.new('presence')
            pre.add_attribute('type', stanza.type) if stanza.type
            pre.add_attribute('from', jid)
            pre.add_attribute('to', stanza.to) if stanza.to
            stanza.xml.elements.each { |elem| pre << elem }

            resource.stream.write pre
        else
            xml = @xml

            xml.each_element do |elem|
                if elem.name == 'presence'
                    elem.add_attribute('to', resource.jid)
                end
            end

            resource.stream.write xml
        end
    end

    #
    # Go through our User's roster and get the relevant
    # entities current presence. This should only be
    # called once, after we send initial presence.
    #
    # I know this seems counter-intuitive. Something should
    # be sending this information TO a Resource, not
    # making the Resource GET it. However, this is
    # the cleanest way to do it in code, and in reality,
    # the former is actually happening.
    #
    def send_roster_presence
        return if @user.roster.nil? or @user.roster.empty?

        # Create a list of roster members we care about.
        roster = @user.roster_subscribed_to
        return unless roster

        roster.each do |j, contact|
            next unless contact.user.available?

            contact.user.resources.each do |name, resource|
                resource.send_presence(self) if resource.available?
            end
        end
    end

    # Broadcast our presence.
    def broadcast_presence(stanza)
        unless stanza.class == Client::PresenceStanza
            raise ArgumentError, "stanza must be a Client::PresenceStanza"
        end

        pre = REXML::Element.new('presence')
        pre.add_attribute('type', stanza.type) if stanza.type
        pre.add_attribute('from', jid)
        stanza.xml.elements.each { |elem| pre << elem }

        @xml = pre

        @state &= ~STATE_AVAILABLE if stanza.type == 'unavailable'

        @user.to_roster_subscribed(pre)
        @user.to_self(pre)
    end
end

end # module XMPP
