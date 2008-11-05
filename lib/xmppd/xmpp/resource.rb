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
require 'xmppd/xmpp'

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
    attr_accessor :dp_to, :presence_stanza
    attr_reader   :name,  :stream, :user

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
    # Broadcast our presence to our subscribed contacts.
    # This is called any time a broadcast presence is issued.
    #
    # return:: [XMPP::Client::Resource] self
    #
    def broadcast_presence
        stanza = @presence_stanza.dup

        @available = false if stanza.attributes['type'] == 'unavailable'

        # Broadcast it to our roster where subscription is 'from' or 'both'.
        # Create a list of roster members who are subscribed to us.
        @user.roster_subscribed_from.each do |jid, myc|
            route = true

            # If it's to a local user we know whether they're online or not.
            if myc.class == DB::LocalContact and not myc.user.available?
                route = false
            end

            if route
                stanza.add_attribute('to', jid)
                @stream.process_stanza(stanza)
            end
        end

        # And also to ourselves.
        stanza.add_attribute('to', jid)
        @stream.process_stanza(stanza)
    end

    def initial_presence
        @available = true

        # If they're sending out initial presense, then they
        # need their contacts' presence.
        #
        # Create a list of roster members we are subscribed to.
        @user.roster_subscribed_to.each do |jid, myc|
            next unless myc.user.available?

            if myc.class == DB::LocalContact
                myc.user.resources.each do |name, rec|
                    next unless rec.available?
                    s = rec.presence_stanza.dup
                    s.add_attribute('to', self.jid)
                    rec.stream.process_stanza(s)
                end
            else
                # XXX - s2s presence probe
            end
        end

        # Do they have any offline stazas?
        return if @user.offline_stanzas.empty?
        return unless @presence_stanza.elements['priority']
        return if @presence_stanza.elements['priority'].text.to_i < 0

        @user.offline_stanzas.each { |stanza| @stream.write stanza }
        @user.offline_stanzas = []
    end

    def send_iq(stanza)
        # Separate out the JID parts.
        node,   domain   = stanza.attributes['to'].split('@')
        domain, resource = domain.split('/')

        # Check to see if it's to a remote user.
        unless $config.hosts.include?(domain)
            @stream.write Stanza.error(stanza, 'feature-not-implemented',
                                       'cancel')
            return
        end

        # Must be to a local user.
        user = DB::User.users[node + '@' + domain]

        unless user
            @stream.write Stanza.error(stanza, 'item-not-found', 'cancel')
            return
        end

        #
        # This is a special case for Service Discovery.
        #
        q = stanza.elements['query']
        if q and not resource and q.attributes['xmlns'] =~ /disco\#(\w+)$/
            methname = "query_disco_#{$1}"

            unless @stream.respond_to?(methname)
                @stream.write Stanza.error(stanza, 'service-unavailable',
                                           'cancel')
                return
            else
                @stream.send(methname, stanza)
                return self
            end
        end

        #
        # This is a special case for roster sets.
        #
        q = stanza.elements['query']
        if q and not resource and q.attributes['xmlns'] == 'jabber:iq:roster'
            @stream.squery_roster(stanza)
            return self
        end if stanza.attributes['type'] == 'set'

        #
        # This is a special case for vCard gets.
        #
        q = stanza.elements['vCard']

        if q and not resource and q.attributes['xmlns'] == 'vcard-temp'
            if stanza.attributes['type'] == 'get'
                @stream.get_vCard(stanza)
            elsif stanza.attributes['type'] == 'set'
                @stream.set_vCard(stanza)
            end

            return self
        end
        
        # Are they online?
        unless user.available?
            @stream.write Stanza.error(stanza, 'service-unavailable', 'cancel')
            return
        end

        # If it's to a specific resource, try to find it.
        if resource and user.resources[resource]
            to_stream = user.resources[resource].stream
        else
            to_stream = user.front_resource.stream

            # The spec is silent on whether we should rewrite the 'to'.
            # Since it says to treat it as a bare JID, I think rewriting
            # it is best.
            stanza.attributes['to'] = user.jid
        end

        # And deliver!
        to_stream.write stanza

        self
    end
end

end # module Client
end # module XMPP
