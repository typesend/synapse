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

# Check for libidn.
begin
    require 'idn'
rescue LoadErrror
    puts 'xmppd: there was an error loading the IDN library'
    puts "xmppd: chances are you just don't have it"
    puts 'xmppd: gem install --remote idn'
    puts 'xmppd: http://rubyforge.org/projects/idn/'
    puts 'xmppd: you must install libidn for this gem to work'
    puts 'xmppd: http://www.gnu.org/software/libidn/'
    exit
end

#
# Import required xmppd modules.
#
require 'xmppd/configure'
require 'xmppd/log'
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

        # Do CLI options.
        opts = OptionParser.new

        cd = 'Use specified configuration file.'
        nd = 'Do not fork into the background.'
        hd = 'Display usage information.'
        vd = 'Display version information.'

        opts.on('-c', '--config FILE', String, cd) { |s| $config_file = s }
        opts.on('-n', '--nofork', nd) { $fork = false }
        opts.on('-h', '-?', '--help', hd) { puts opts.to_s; exit! }
        opts.on('-v', '--version', vd) { exit! } # Already displayed.

        begin
            opts.parse(*ARGV)
        rescue OptionParser::InvalidOption => e
            puts e
            puts opts.to_s
            exit!
        end

        # Set up our configuration data.
        begin
            Configure.load($config_file)
        rescue Exception => e
            puts '----------------------------'
            puts "xmppd: configure error: #{e}"
            puts '----------------------------'
            raise
        end

        # Initialize logging.
        $log = MyLog::MyLogger.instance

        $log.xmppd.unknown '-!- new logging session started -!-'
        $log.c2s.unknown '-!- new logging session started -!-'
        $log.s2s.unknown '-!- new logging session started -!-'
    end

    def ioloop
        puts "There is nothing to do yet."
        exit

        # Exiting...
        my_exit
    end

    def my_exit
        # Exiting, clean up.
        $log.xmppd.unknown '-!- terminating normally -!-'
        $log.c2s.unknown '-!- terminating normally -!-'
        $log.s2s.unknown '-!- terminating normally -!-'

        $log.xmppd.close
        $log.c2s.close
        $log.s2s.close
    end
end
