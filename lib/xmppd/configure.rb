#
# xmppd: a small XMPP server
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
require 'xmppd/configure/listen'
require 'xmppd/configure/logging'
require 'xmppd/configure/operator'

require 'xmppd/var.rb'

#
# Import required Ruby modules.
#
require 'rexml/document'

#
# The configuration namespace.
#
module Configure

extend self

#
# An exception raised when there's problems with the configuration data.
#
class ConfigureError < Exception
end

#
# Get the configuration data from a file and feed it to REXML.
#
def load(filename)
    begin
        data = open(filename, 'r').read
    rescue Exception => e
        puts "xmppd: couldn't open configuration file: #{e}"
        exit
    end

    $config = Configure::Configuration.new

    begin
        xml = REXML::Document.new(File.open(filename))
    rescue REXML::ParserError => e
        puts 'xmppd: configuration error: %s' % e
        exit
    end

    # Now go through and set everything in our $config.
    xml.root.elements.each do |elem|
       meth = 'do_' + elem.name.sub('-', '_')
       if respond_to? meth
          send(meth, elem)
       else
          raise ConfigureError, "Unknown element: #{elem.name}"
       end
    end
end

def do_virtual_host(elem)
    raise ConfigureError, 'virtual_host has no text' unless elem.text
    $config.virtual_host << elem.text
end

def do_logging(elem)
    unless $config.logging.general.empty?
        raise ConfigureError, 'multiple logging elements'
    end

    unless elem.respond_to? 'elements'
        raise ConfigureError, 'logging has no elements'
    end

    general, c2s, s2s = false

    elem.elements.each do |subelem|
        raise ConfigureError, "{#subelem.name} has no text" unless subelem.text

        case subelem.name
        when 'general'
            $config.logging.general = subelem.text
            general = true
        when 'c2s'
            $config.logging.c2s = subelem.text
            c2s = true
        when 's2s'
            $config.logging.s2s = subelem.text
            s2s = true
        else
            raise ConfigureError, "unknown logging element: {#subelm.name}"
        end
     end

    raise ConfigureError, 'missing logging element: general' unless general
    raise ConfigureError, 'missing logging element: c2s' unless c2s
    raise ConfigureError, 'missing logging element: s2s' unless s2s
end

def do_listen(elem)
    unless elem.respond_to? 'elements'
        raise ConfigureError, 'listen has no elements'
    end

    newlisten = Configure::Listen.new
    c2s, s2s = false
    port = 0

    elem.attributes.each do |name, value|
        case name
        when 'host'
            newlisten.host = value
        else
            raise ConfigureError, "unknown listen attribute: {#name}"
        end
    end

    elem.elements.each do |subelem|
        raise ConfigureError, "{#subelem.name} has no text" unless subelem.text

        case subelem.name
        when 'port'
            unless subelem.respond_to? 'attributes'
                raise ConfigureError, "port has no attributes (need 'type')"
            end

            subelem.attributes.each do |name, value|
                case name
                when 'type'
                    case value
                    when 'c2s'
                        newlisten.c2s << subelem.text.to_i
                        c2s = true
                    when 's2s'
                        newlisten.s2s << subelem.text.to_i
                        s2s = true
                    end
                else
                    raise ConfigureError, "unknown port attribute: #{name}"
                end
            end

            port += 1
        else
            raise ConfigureError, "unknown listen element: #{subelem.name}"
        end
    end

    raise ConfigureError, 'missing listen element: port' unless port >= 2
    raise ConfigureError, 'missing port type: c2s' unless c2s
    raise ConfigureError, 'missing port type: s2s' unless s2s

    $config.listen << newlisten
end

def do_auth(elem)
    unless elem.respond_to? 'elements'
        raise ConfigureError, 'auth has no elements'
    end

    newauth = Configure::Auth.new
    ip = false

    unless elem.respond_to? 'attributes'
        raise ConfigureError, "auth has no attributes (need 'type')"
    end

    elem.attributes.each do |name, value|
        case name
        when 'virtual_host'
            newauth.virtual_host = value
        when 'type'
            case value
            when 'allow'
                newauth.type = value
                type = true
            when 'deny'
                newauth.type = value
                type = true
            end
        else
            raise ConfigureError, "unknown auth attribute: #{name}"
        end

        raise ConfigureError, 'missing auth attribute: type' unless newauth.type
    end

    elem.elements.each do |subelem|
        if subelem.name == 'ip' or subelem.name == 'match'
            unless subelem.text
                raise ConfigureError, "#{subelem.name} has no text"
            end
        end

        case subelem.name
        when 'ip'
            newauth.ip << subelem.text
            ip = true
        when 'match'
            newauth.match << /#{subelem.text}/
            ip = true # ip/match is xs:choice
        when 'plain'
            newauth.plain = true
        when 'legacy_auth'
            newauth.legacy_auth = true
        else
            raise ConfigureError, "unknown auth element: #{subelem.name}"
        end
    end

    raise ConfigureError, 'missing auth element: ip' unless ip

    $config.auth << newauth
end

def do_operator(elem)
    unless elem.respond_to? 'elements'
        raise ConfigureError, 'operator has no elements'
    end

    newop = Configure::Operator.new
    jid = false

    elem.attributes.each do |name, value|
        case name
        when 'virtual_host'
            newop.virtual_host = value
        end
    end if elem.respond_to? 'attributes'

    elem.elements.each do |subelem|
        case subelem.name
        when 'jid'
            unless subelem.text =~ /^(\w+)\@[(\w\.?)]+$/
                raise ConfigureError, "#{subelem.text} not a valid JID"
            end

            newop.jid << subelem.text
            jid = true
        when 'announce'
            newop.announce = true
        else
            raise ConfigureError, "unknown operator element: #{subelem.name}"
        end
    end

    raise ConfigureError, 'missing operator element: jid' unless jid

    $config.operator << newop
end

def do_not_configured(elem)
#    puts "xmppd: you didn't read the configuration file."
#    exit
end

end # module Configure
