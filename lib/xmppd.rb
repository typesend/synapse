#
# xmppd: a small XMPP server
# xmppd.rb: main program class
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'optparse'
require 'singleton'

#
# Import required xmppd modules.
#
require 'xmppd/configure'
require 'xmppd/var'
require 'xmppd/version'

#
# The main program class.
#
class XMPPd
    include Singleton

    def initialize
        if RUBY_VERSION.to_f < 1.8
            puts 'xmppd: requires at least ruby 1.8'
            puts 'xmppd: you have: %s' % `ruby -v`
            exit
        end

        puts "xmppd: version #$version (#$release_date) [#{RUBY_PLATFORM}]"

        # Check to see if we're running as root.
        if Process.euid == 0
            puts "xmppd: don't run XMPP as root."
            exit
        end

        # Set up our configuration data.
        Configure.load($config_file)
    end

    def ioloop
        puts "There is nothing to do yet."
        exit
    end
end
