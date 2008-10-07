#
# synapse: a small XMPP server
# xmpp/resource.rb: handles client resources
#
# Copyright (c) 2006-2008 Eric Will <rakaur@malkier.net>
#
# $Id$
#

# Import required xmppd modules.
require 'xmppd/db'
require 'xmppd/xmpp/stream'

# The XMPP namespace.
module XMPP

# The Client namespace.
module Client

#
# This is our XMPP::Client::Resource class.
# This class handles all stuff a resource would
# receive, such as rosters, presence notifications, etc.
#
class Resource
    attr_accessor :presence_stanza
    attr_reader   :dp_to, :name, :stream, :user

    #
    # Create a new XMPP::Client::Resource.
    #
    # name:: [String] the resource's name
    # stream:: [XMPP::ClientStream] the associated stream
    # user:: [DB::User] the stored user, where the roster and such is kept.
    #
    # return:: [XMPP::Client::Resource] new resource object.
    #
    def initialize(name, stream, user)
        @dp_to      = []    # JIDs that we've sent directed presence to.
        @name       = name  # The resource name.
        @available  = false # True on initial presence.
        @interested = false # True on roster get.

        # This is the ClientStream that bound us.
        unless stream.class == ClientStream
            raise ArgumentError, "stream isn't a client stream"
        end

        @stream = stream

        # This is the stored user, where the roster and such is kept.
        unless user.class == DB::User
            raise ArgumentError, "user isn't a db user"
        end

        @user = user

        # We're bound to the user, now bind them to us.
        @user.add_resource(self)
    end
    
    ######
    public
    ######

    #
    # Return our full JID.
    #
    # return:: [String] the Resource's full JID: node@domain/resource
    #
    def jid
        @user.jid + '/' + @name
    end
    

    #
    # Set the resource's interest in presence updates.
    #
    # value:: [boolean] true or false
    #
    # return:: [boolean] true or false
    #
    def available=(value)
        unless value == true or value == false
            raise ArgumentError, 'value must be true or false'
        end

        @available = value
    end

    #
    # Has the resource requested presence updates?
    #
    # return:: [boolean] true or false
    #
    def available?
        @available
    end

    #
    # Set the resource's interest in roster pushes.
    #
    # value:: [boolean] true or false
    #
    # return:: [boolean] true or false
    #
    def interested=(value)
        unless value == true or value == false
            raise ArgumentError, 'value must be true or false'
        end

        @interested = value
    end

    #
    # Has the resource requested roster pushes?
    #
    # return:: [boolean] true or false
    #
    def interested?
        @interested
    end

    #
    # Send directed presence to one JID.
    #
    # jid:: [String] full or bare JID
    # stanza:: [REXML::Element] the stanza to send
    #
    # return:: [XMPP::Client::Resource] self
    #
    def send_directed_presence(jid, stanza)
        unless stanza.class == REXML::Element
            raise ArgumentError, 'stanza must be a REXML::Element'
        end

        # Separate out the JID parts.
        node,   domain   = jid.split('@')
        domain, resource = domain.split('/')

        # Check to see if its to a local user.
        return unless $config.hosts.include?(domain)

        user = DB::User.users[node + '@' + domain]

        if user and not user.resources.empty?
            sb = user.subscribed?(@user)

            if resource and user.resources[resource]
                send_presence(user.resources[resource], stanza)
                @dp_to << user.resources[resource].jid unless sb
                return self
            else
                user.resources.each do |n, resource|
                    send_presence(resource, stanza)
                    @dp_to << resource.jid unless sb
                end

                return self
            end
        end

        # XXX - If we get here then they're s2s.

        return self
    end

    #
    # Send our presence to one resource.
    #
    # resource:: [XMPP::Client::Resource] resource to send it to
    # stanza:: [REXML::Element] send using specific stanza
    #
    # return:: [XMPP::Client::Resource] self
    #
    def send_presence(resource, stanza = nil)
        unless resource.class == Resource
            raise ArgumentError, 'resource must be a XMPP::Client::Resource'
        end

        unless stanza.class == REXML::Element
            raise ArgumentError, 'stanza must be a REXML::Element'
        end if stanza

        if stanza
            stanza.add_attribute('from', jid)

            resource.stream.write stanza
        else
            @presence_stanza.add_attribute('from', jid)
            @presence_stanza.add_attribute('to',   resource.jid)

            resource.stream.write @presence_stanza

            @presence_stanza.attributes.delete('to')
        end
    end

    #
    # Get our roster's current presence information.
    # This should only be called upon initial presence.
    #
    # return:: [XMPP::Client::Resource] self
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

    #
    # Broadcast our presence to our subscribed contacts.
    # This is called any time a broadcast presence is issued.
    #
    # return:: [XMPP::Client::Resource] self
    #
    def broadcast_presence(stanza)
        unless stanza.class == REXML::Element
            raise ArgumentError, 'stanza must be a REXML::Element'
        end

        stanza.add_attribute('from', jid)

        @available = false if stanza.attributes['type'] == 'unavailable'

        @user.to_roster_subscribed(stanza)
        @user.to_self(stanza) unless stanza.attributes['type'] == 'unavailable'

        self
    end
end

end # module Client
end # module XMPP
