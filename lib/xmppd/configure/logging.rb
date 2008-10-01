#
# synapse: a small XMPP server
# logging.rb: logging configuration
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'logger'

module Configure

#
# Represents logging{} configuration data.
#
class Logging
    attr_accessor :xmppd, :c2s, :s2s
    attr_reader :enable, :level

    def initialize
        @xmppd = nil
        @c2s = nil
        @s2s = nil
        @enable = false
        @level = nil
    end

    def enable=(value)
        unless value == true || value == false
            raise ArgumentError, "invalid 'enable' (must be true/false)"
        end

        @enable = value
    end

    def level=(value)
       case value.downcase
       when 'fatal'
           @level = Logger::FATAL

       when 'error' 
           @level = Logger::ERROR

       when 'warning'
           @level = Logger::WARN

       when 'info'
           @level = Logger::INFO

       when 'debug'
           @level = Logger::DEBUG

       else
           raise ArgumentError, 'invalid level (must be valid Logger level)'
       end
    end
end

end # module Configure
