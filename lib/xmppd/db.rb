#
# synapse: a small XMPP server
# db.rb: database classes
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'digest/md5'
require 'idn'
require 'rexml/document'
require 'yaml'

#
# Import required xmppd modules.
#
require 'xmppd/xmpp/stanza'

#
# The DB namespace.
#
module DB

extend self

#
# Database exception.
#
class DBError < Exception
end

#
# Represents a registered user.
#
class User
    @@users = {}
    @@need_dump = false

    attr_accessor :offline_stanzas, :vcard
    attr_reader   :node, :domain, :password, :resources, :roster

    def initialize(node, domain, password)
        @resources = {}
        @roster = {}
        @offline_stanzas = { 'iq'       => [],
                             'presence' => [],
                             'message'  => [] }

        @node = IDN::Stringprep.nodeprep(node[0, 1023])

        if domain =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/
            @domain = domain
        else
            @domain = IDN::Stringprep.nameprep(domain[0, 1023])
        end

        unless $config.hosts.include?(@domain)
            raise DBError, "we do not serve host: #{@domain}"
        end

        @password = "%s:%s:%s" % [@node, @domain, password]
        @password = Digest::MD5.digest(@password)

        raise DBError, "#{jid} already exists" if @@users[jid]

        @@users[jid] = self

        $log.xmppd.info "new user: #{jid}"

        @@need_dump = true
    end

    ######
    public
    ######

    def to_yaml_properties
        %w( @node @domain @password @roster @offline_stanzas @vcard )
    end

    def User.users
        @@users
    end

    def User.need_dump?
        true #@@need_dump -- XXX figure out offline_stanzas
    end

    def User.load
        begin
            File.open('var/db/users.yaml') do |f|
                @@users = YAML.load(f)
                @@users ||= {}
            end
        rescue Exception => e
            puts "xmppd: failed to load user database: #{e}"
            exit
        else
            $log.xmppd.info "loaded #{@@users.length} users"
        end
    end

    def User.dump
        return unless need_dump?

        # Prune away empty entries.
        @@users.delete_if { |k, v| v.nil? } if @@users.has_value?(nil)

        @@users.each do |uk, uv|
            uv.roster.delete_if { |k, v| v.nil? } if uv.roster.has_value?(nil)
        end

        begin
            Dir.mkdir('var/db') unless File.exists?('var/db')

            File.open('var/db/users.yaml', 'w') { |f| YAML.dump(@@users, f) }
        rescue Exception => e
            $log.xmppd.warn "failed to write user database: #{e}"
            return false
        else
            $log.xmppd.info "wrote #{@@users.length} users"
            @@need_dump = false
            return true
        end
    end

    def User.auth(jid, password, plain = false)
        return false unless @@users[jid]

        if plain
            node, domain = jid.split('@')
            check = "%s:%s:%s" % [node, domain, password]
            check = Digest::MD5.digest(check)

            return true if check == @@users[jid].password
        else
            return true if password == @@users[jid].password
        end

        return false
    end

    def User.delete(jid)
        raise DBError, "#{jid} does not exist" unless @@users[jid]

        user = @@users[jid]
        @@users.delete(jid)

        # Disconnect any active resources.
        user.resources.each { |n, rec| rec.stream.close } if user.resources

        # XXX - remove them from rosters?
        user.roster.each do |c|
        end

        $log.xmppd.info "user delete: #{jid}"

        @@need_dump = true
    end

    def jid
        @node + '@' + @domain
    end

    def operator?
        m = $config.operator.find { |oper| oper.jid == jid }
        return false unless m
        return m
    end

    def password=(newpass)
        newpass = "%s:%s:%s" % [@node, @domain, newpass]
        @password = Digest::MD5.digest(newpass)

        $log.xmppd.info 'password change for %s' % jid

        @@need_dump = true
    end

    def add_contact(contact)
        unless contact.kind_of?(Contact)
            raise DBError, "contact isn't a Contact class"
        end

        @roster[contact.jid] = contact

        $log.xmppd.debug "DB::User.add_contact(): #{jid} -> #{contact.jid}"

        @@need_dump = true
    end

    def delete_contact(ujid)
        if @roster[ujid]
            @roster.delete(ujid)

            $log.xmppd.debug "DB::User.delete_contact(): #{jid} -> #{ujid}"

            @@need_dump = true
        end
    end

    def add_resource(resource)
        unless resource.class == XMPP::Client::Resource
            raise DBError, "resource isn't a Resource class"
        end

        @resources ||= {}
        @resources[resource.name] = resource
    end

    def delete_resource(resource)
        unless resource.class == XMPP::Client::Resource
            raise DBError, "resource isn't a Resource class"
        end

        @resources.delete_if { |j, rec| rec == resource }
    end

    # True if we have any connected resources.
    def available?
        $-w = false
        if @resources.nil? or @resources.empty?
            return false
        else
            return true
        end
        $-w = true
    end

    # True if we're subscribed to their presence.
    def subscribed?(user)
        return true if user == self

        myc = @roster[user.jid]
        return false unless myc

        return true if myc.subscription == 'to'
        return true if myc.subscription == 'both'

        return false
    end

    #
    # Return the resource with the highest priority.
    #
    def front_resource
        recs = {}

        # If there is a tie, the last one in the loop wins.
        @resources.each do |name, rec|
            next unless rec.available?
            next unless rec.presence_stanza.elements['priority']
            p = rec.presence_stanza.elements['priority'].text.to_i
            next if p < 0 # Skip negative priorities.

            recs[p] = rec
        end

        return recs[recs.keys.max]
    end

    #
    # Returns an array of Contacts in our roster that
    # are subscribed to our presence.
    #
    def roster_subscribed_from
        @roster.find_all { |j, contact| contact.user.subscribed?(self) }
    end

    #
    # Returns an array of Contacts in our roster that
    # we are subscribed to.
    def roster_subscribed_to
        @roster.find_all { |j, contact| subscribed?(contact) }
    end

    # Send a given xml stanza to ourselves.
    def to_self(xml)
        return unless available?

        @resources.each do |name, resource|
            next unless resource.interested?

            xml.root.add_attribute('to', resource.jid)
            resource.stream.write xml
        end
    end

    #
    # Send a given xml stanza to all of the entries in our roster
    # where subscription is either "FROM" or "BOTH."
    #
    def to_roster_subscribed(xml)
        return if @roster.empty?

        # Create a list of roster members who are subscribed to us.
        roster = roster_subscribed_from
        return unless roster

        roster.each do |j, contact|
            next if contact.class == RemoteContact # XXX - haven't done s2s yet...

            # Do they have any online resources?
            next unless contact.user.available?

            # Now go through each of their online resources and send it.
            contact.user.resources.each do |name, resource|
                next unless resource.interested?
                next unless resource.available?

                xml.root.add_attribute('to', resource.jid)

                resource.stream.write xml 
            end
        end
    end

    def roster_to_xml
        query = XMPP::Stanza.new_query('jabber:iq:roster')
        @roster.each { |name, contact| query << contact.to_xml }
        return query
    end

    def clean_roster
        return unless @roster
        return if @roster.empty?

        @roster.each do |j, c|
            if c.subscription == 'none' and c.pending_none?
                delete_contact(j)

                if available?
                    #
                    # God, Ruby's threads are totally useless. I can't even
                    # get a thread to look at stanza.rb because *something*
                    # happens and everything stops working.
                    #
                    iq    = REXML::Element.new('iq')
                    query = REXML::Element.new('query')
                    item  = REXML::Element.new('item')

                    iq.add_attribute('id', 'rubysucks')
                    iq.add_attribute('type', 'set')

                    query.add_namespace('jabber:iq:roster')

                    item.add_attribute('jid', j)
                    item.add_attribute('subscription', 'remove')
                    puts "added the attributes.."

                    query << item
                    iq    << query

                    @resources.each { |n, rec| rec.stream.write iq }
                end
            end

            next unless c.pending_out?

            if ($time - c.stime) >= 86400 # One day.
                presence = REXML::Element.new('presence')
                presence.add_attribute('type', 'subscribe')
                presence.add_attribute('to', j)
                presence.add_attribute('from', jid)

                if available?
                    front_resource.send_directed_presence(j, presence)
                    c.stime = $time
                end
            end
        end
    end
end

#
# A contact in a roster.
#
class Contact
    attr_accessor :groups, :name, :pending, :stime
    attr_reader   :subscription

    PEND_NONE = 0x00000000
    PEND_IN   = 0x00000001
    PEND_OUT  = 0x00000002

    def initialize
        @groups = []
        @name = nil
        @subscription = 'none'
        @pending = PEND_NONE
    end

    ######
    public
    ######

    def subscription=(value)
        unless value =~ /^(to|from|both)$/
            raise ArgumentError, "subscription must be 'to', 'from', or 'both'"
        end

        @subscription = value
    end

    def pending_in=(value)
        unless value == true or value == false
            raise ArgumentError, 'value must be true or false'
        end

        if value
            @pending |= PEND_IN
        else
            @pending &= ~PEND_IN
        end
    end

    def pending_out=(value)
        unless value == true or value == false
            raise ArgumentError, 'value must be true or false'
        end

        if value 
            @pending |= PEND_OUT
        else
            @pending &= ~PEND_OUT
        end
    end

    def pending_none=(value)
        unless value == true or value == false
            raise ArgumentError, 'value must be true'
        end

        @pending = PEND_NONE
    end

    def pending_none?
        return (@pending == PEND_NONE) ? true : false
    end

    def pending_in?
        return (PEND_IN & @pending != 0) ? true : false
    end

    def pending_out?
        return (PEND_OUT & @pending != 0) ? true : false
    end

    def to_xml
        item = REXML::Element.new('item')
        item.add_attribute('jid', self.jid)
        item.add_attribute('name', @name) if @name
        item.add_attribute('subscription', @subscription)

        item.add_attribute('ask', 'subscribe') if pending_out?

        @groups.each do |g|
            group = REXML::Element.new('group')
            group.text = g
            item << group
        end if @groups

        item
    end
end

class LocalContact < Contact
    attr_reader :user

    def initialize(user)
        super()

        raise DBError, 'user is not a DB::User' unless user.class == User

        @user = user
    end

    ######
    public
    ######

    def to_yaml_properties
        %w( @user @stime @subscription @pending @name @groups )
    end

    def jid
        @user.jid
    end
end

class RemoteContact < Contact
    attr_reader :node, :domain, :resources

    def initialize(node, domain, resource = nil)
        super()

        @resources = []
        @node = IDN::Stringprep.nodeprep(node)
        @domain = IDN::Stringprep.nameprep(domain)

        add_resource(resource) if resource
    end

    ######
    public
    ######

    def to_yaml_properties
        %w( @node @stime @domain @subscription @pending @name @groups )
    end

    def jid
        @node + '@' + @domain
    end

    def add_resource(resource)
        @resources << IDN::Stringprep.resourceprep(resource)
    end

    def delete_resource(resource)
        @resources.delete_if { |r| r == resource }
    end
end

end # module DB
