#
# xmppd: a small XMPP server
# log.rb: logging subsystem
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'logger'
require 'singleton'

#
# Import required xmppd modules.
#
require 'xmppd/var'

#
# MyLog namespace
#
module MyLog

class MyFormatter < Logger::Formatter
    def f
    end
end

#
# Our logging class.
#
class MyLogger
    include Singleton

    attr_accessor :xmppd, :c2s, :s2s

    # I'm not sure why I don't need to prefix Logger:: here,
    # because I'm not including it. Maybe I'm in the same
    # namespace as Ruby's Logger somewhere, but I don't
    # really care and it works, so, neener.
    def initialize

        if $fork
            @xmppd = Logger.new($config.logging.xmppd, 'weekly')
            @c2s = Logger.new($config.logging.c2s, 'weekly')
            @s2s = Logger.new($config.logging.s2s, 'weekly')
        else
            @xmppd = Logger.new($stdout)
            @c2s = Logger.new($stdout)
            @s2s = Logger.new($stdout)
        end

        @xmppd.level, @xmppd.progname  = $config.logging.level, 'xmppd'
        @c2s.level, @c2s.progname = $config.logging.level, 'c2s'
        @s2s.level, @s2s.progname = $config.logging.level, 's2s'

        @xmppd.datetime_format = '%b %d %H:%M:%S '
        @c2s.datetime_format = '%b %d %H:%M:%S '
        @s2s.datetime_format = '%b %d %H:%M:%S '
    end
end

end # module Log
