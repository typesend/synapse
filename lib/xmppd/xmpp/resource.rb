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
    attr_accessor :state
    attr_reader :name, :stream, :user, :priority, :show, :status
    
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

    # Send our presence to one Resource.
    def send_presence(resource)
        unless resource.class == Resource
            raise ArgumentError, "resource must be a Resource class"
        end

        xml = REXML::Document.new
        pre = REXML::Element.new('presence')
        pre.add_attribute('to', resource.jid)
        pre.add_attribute('from', jid)

        pri = REXML::Element.new('priority')
        pri.text = @priority.to_s

        pre << pri

        show = REXML::Element.new('show')
        case @show
        when SHOW_AVAILABLE
            show = nil
        when SHOW_AWAY
            show.text = 'away'
        when SHOW_CHAT
            show.text = 'chat'
        when SHOW_DND
            show.text = 'dnd'
        when SHOW_XA
            show.text = 'xa'
        end

        pre << show if show

        if @status
            status = REXML::Element.new('status')
            status.text = @status

            pre << status
        end

        xml << pre

        resource.stream.write xml
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

        xml = REXML::Document.new

        pre = REXML::Element.new('presence')
        pre.add_attribute('type', stanza.type) if stanza.type
        pre.add_attribute('from', jid)
        stanza.xml.elements.each { |elem| pre << elem }

        xml << pre

        @user.to_roster_subscribed(xml)
        @user.to_self(xml)
    end
end

end # module XMPP
