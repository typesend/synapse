#
# xmppd: a small XMPP server
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

    attr_reader :node, :domain, :password, :resources

    def initialize(node, domain, password)
        @resources = {}

        @node = IDN::Stringprep.nodeprep(node)

        unless domain =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/
            @domain = IDN::Stringprep.nameprep(domain)
        end

        @password = "%s:%s:%s" % [@node, @domain, password]
        @password = Digest::MD5.digest(@password)

        raise DBError, "#{jid} already exists" if @@users[jid]

        @@users[jid] = self

        $log.xmppd.info 'new user: %s' % jid
    end

    ######
    public
    ######

    def to_yaml_properties
        %w( @node @domain @password )
    end

    def User.users
        # Prune away empty entries.
        @@users.delete_if { |k, v| v.nil? } if @@users.has_value?(nil)

        @@users
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
        begin
            Dir.mkdir('var/db') unless File.exists?('var/db')

            File.open('var/db/users.yaml', 'w') do |f|
                YAML.dump(@@users, f)
            end
        rescue Exception => e
            $log.xmppd.warn "failed to write user database: #{e}"
            return false
        else
            $log.xmppd.info "wrote #{@@users.length} users"
            return true
        end
    end

    def User.auth(jid, password, plain = false)
        unless @@users[jid]
            return false
        end

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
    end

    def jid
        @node + '@' + @domain
    end

    def password=(newpass)
        newpass = "%s:%s:%s" % [@node, @domain, newpass]
        @password = Digest::MD5.digest(newpass)

        $log.xmppd.info 'password change for %s' % jid
    end

    def add_resource(resource)
        unless resource.class == Resource
            raise DBError, "resource isn't a Resource class"
        end

        @resources[resource.name] = resource
    end
end

end # module DB
