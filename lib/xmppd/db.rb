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

    attr_reader :node, :domain, :password, :resources, :roster

    # XXX - something's wrong with IPs here
    def initialize(node, domain, password)
        @resources = {}
        @roster = {}

        @node = IDN::Stringprep.nodeprep(node[0, 1023])

        unless domain =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/
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
        %w( @node @domain @password @roster )
    end

    def User.users
        @@users
    end

    def User.need_dump?
        @@need_dump
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

        @@users[jid] = nil
        @@need_dump = true
    end

    def jid
        @node + '@' + @domain
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

        # If it's one of ours, make sure we add it to their roster, too.
        if contact.class == LocalContact
            return if contact.user.roster[jid] # XXX - updating theirs? infinite loop...

            nlc = LocalContact.new(self)

            case contact.subscription
            when Contact::SUB_TO
                nlc.subscription = Contact::SUB_FROM
            when Contact::SUB_FROM
                nlc.subscription = Contact::SUB_TO
            when Contact::SUB_BOTH
                nlc.subscription = Contact::SUB_BOTH
            end

            contact.user.add_contact(nlc)
        end

        @@need_dump = true
    end

    def delete_contact(ujid)
        if @roster[ujid]
            @roster[ujid] = nil

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
        myc = @roster[user.jid]
        return false unless myc

        return true if myc.subscription == Contact::SUB_TO
        return true if myc.subscription == Contact::SUB_BOTH

        return false
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
        query = REXML::Element.new('query')
        query.add_namespace('jabber:iq:roster')

        @roster.each do |k, c|
            item = REXML::Element.new('item')
            item.add_attribute('jid', c.jid)
            item.add_attribute('name', c.name) if c.name

            case c.subscription
            when Contact::SUB_NONE
                item.add_attribute('subscription', 'none')
            when Contact::SUB_TO
                item.add_attribute('subscription', 'to')
            when Contact::SUB_FROM
                item.add_attribute('subscription', 'from')
            when Contact::SUB_BOTH
                item.add_attribute('subscription', 'both')
            end

            query << item
        end

        query
    end
end

#
# A contact in a roster.
#
class Contact
    attr_reader :name
    attr_accessor :subscription, :pending

    SUB_NONE  = 0x00000000
    SUB_TO    = 0x00000001
    SUB_FROM  = 0x00000002
    SUB_BOTH  = 0x00000004

    PEND_NONE = 0x00000000
    PEND_IN   = 0x00000001
    PEND_OUT  = 0x00000002

    def initialize
        @subscription = SUB_NONE
        @pending = PEND_NONE
        @name = nil
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
        %w( @user @subscription @pending @name )
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
        %w( @node @domain @subscription @pending @name )
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
