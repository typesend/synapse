#
# synapse: a small XMPP server
# configure.rb: configuration management
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required xmppd modules.
#
require 'xmppd/configure/auth'
require 'xmppd/configure/configuration'
require 'xmppd/configure/deny'
require 'xmppd/configure/listen'
require 'xmppd/configure/logging'
require 'xmppd/configure/operator'
require 'xmppd/configure/parser'

require 'xmppd/var'

#
# Import required Ruby modules.
#
require 'idn'
require 'openssl'

#
# The configuration namespace.
#
module Configure

extend self

#
# Get the configuration data from a file and feed it to the parser.
#
def load(filename)
    begin
        data = open(filename, 'r').read
    rescue Exception => e
        puts "xmppd: couldn't open configuration file: #{e}"
        exit
    end

    $config = Configure::Configuration.new

    parser = Configure::ConfigParser.new

    begin
        parser.feed(data)
        parser.parse
    rescue Configure::ConfigError => e
        puts 'xmppd: configuration error: %s' % e
        exit
    end
end

#
# Our subclassed ConfigParser. Takes care of setting all the useful
# little switches in our Configuration.
#
class ConfigParser < Configure::Parser
    def initialize
        super
    end

    def handle_hosts(entry)
       entry.entries.each do |node|
           $config.hosts << IDN::Stringprep.nameprep(node.name[0, 1023])
       end
    end

    def handle_logging(entry)
        entry.entries.each do |node|
            methname = 'handle_log_%s' % node.name

            if respond_to? methname
                send(methname, node)
            else
                unknown_directive(node.name, node.name)
            end
        end
    end

    def handle_log_enable(entry)
        $config.logging.enable = true
    end

    def handle_log_xmppd_path(entry)
        missing_parameter(entry.name, entry.line) unless entry.data
        $config.logging.xmppd = entry.data
    end

    def handle_log_c2s_path(entry)
        miss_parameter(entry.name, entry.line) unless entry.data
        $config.logging.c2s = entry.data
    end

    def handle_log_s2s_path(entry)
        missing_parameter(entry.name, entry.line) unless entry.data
        $config.logging.s2s = entry.data
    end

    def handle_log_level(entry)
        missing_parameter(entry.name, entry.line) unless entry.data
        $config.logging.level = entry.data
    end

    def handle_listen(entry)
        entry.entries.each do |node|
            methname = 'handle_ports_%s' % node.name

            if respond_to? methname
                send(methname, node)
            else
                unknown_directive(node.name, node.name)
            end
        end

        unless $config.listen.certfile
            puts 'xmppd: no certfile set'
            exit
        end

        unless File.exists?($config.listen.certfile)
            puts 'xmppd: specified certfile does not exist'
            exit
        end

        begin
           cert = OpenSSL::X509::Certificate.new(File::read($config.listen.certfile))
           pkey = OpenSSL::PKey::RSA.new(File::read($config.listen.certfile))
           $ctx = OpenSSL::SSL::SSLContext.new
           $ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
           $ctx.cert = cert
           $ctx.key = pkey
        rescue Exception => e
            puts 'xmppd: OpenSSL error: ' + e.to_s
            raise
        end
    end

    def handle_ports_c2s(entry)
        entry.entries.each do |node|
            host, port = node.name.split(':')

            $config.listen.c2s << { 'host' => host,
                                    'port' => port.to_i }
        end
    end

    def handle_ports_s2s(entry)
        entry.entries.each do |node|
            host, port = node.name.split(':')

            $config.listen.s2s << { 'host' => host,
                                    'port' => port.to_i }
        end
    end

    def handle_ports_certfile(entry)
        missing_parameter(entry.name, entry.line) unless entry.data

        $config.listen.certfile = entry.data
    end

    def handle_auth(entry)
        newauth = Configure::Auth.new

        entry.entries.each do |node|
            case node.name
            when 'host'
                missing_parameter(node.name, node.line) unless node.data
                newauth.host << node.data

            when 'match'
                missing_parameter(node.name, node.line) unless node.data
                newauth.match << /#{node.data}/

            when 'timeout'
                missing_parameter(node.name, node.line) unless node.data
                newauth.timeout = node.data.to_i

            when 'flags'
                node.entries.each do |flag|
                    case flag.name
                    when 'plain'
                        newauth.plain = true

                    when 'legacy_auth'
                        newauth.legacy_auth = true

                    else
                        unknown_directive(node.name, node.name)
                    end
                end
            else
                unknown_directive(node.name, node.name)
            end
        end

        $config.auth << newauth
    end

    def handle_deny(entry)
        newdeny = Configure::Deny.new

        entry.entries.each do |node|
            missing_parameter(node.name, node.line) unless node.data

            case node.name
            when 'host'
                newdeny.host << node.data

            when 'match'
                newdeny.match << /#{node.data}/

            else
                unknown_directive(node.name, node.name)
            end
        end

        $config.deny << newdeny
    end

    def handle_operator(entry)
        newoper = Configure::Operator.new

        missing_parameter(entry.name, entry.line) unless entry.data

        newoper.jid = entry.data

        entry.entries.each do |node|
            case node.name
            when 'flags'
                node.entries.each do |flag|
                    case flag.name
                    when 'announce'
                        newoper.announce = true
                    else
                        unknown_directive(flag.name, flag.name)
                    end
                end
            else
                unknown_directive(node.name, node.name)
            end
        end

        $config.operator << newoper
    end

    def handle_die(entry)
        puts "xmppd: you didn't read the configuration file"
        exit
    end
end

end # module Configure
