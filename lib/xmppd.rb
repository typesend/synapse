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
require 'xmppd/listen'
require 'xmppd/log'
require 'xmppd/var'
require 'xmppd/version'
require 'xmppd/xmpp/stream'

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
        dd = 'Enable debug mode.'
        nd = 'Do not fork into the background.'
        hd = 'Display usage information.'
        vd = 'Display version information.'

        opts.on('-c', '--config FILE', String, cd) { |s| $config_file = s }
        opts.on('-d', '--debug', dd) { $debug = true }
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

        # Handle signals and such.
        Signal.trap('INT') do
            $log.xmppd.info 'caught interrupt'
            exit
        end

        Signal.trap('HUP') do
            # XXX - rehash
        end

        Signal.trap('PIPE', 'SIG_IGN')
        Signal.trap('ALRM', 'SIG_IGN')
        Signal.trap('CHLD', 'SIG_IGN')
        Signal.trap('WINCH', 'SIG_IGN')
        Signal.trap('TTIN', 'SIG_IGN')
        Signal.trap('TTOU', 'SIG_IGN')
        Signal.trap('TSTP', 'SIG_IGN')

        # Set up our configuration data.
        begin
            Configure.load($config_file)
        rescue Exception => e
            puts '----------------------------'
            puts "xmppd: configure error: #{e}"
            puts '----------------------------'
            raise
        end

        if $debug
            puts 'xmppd: warning: debug mode enabled'
            puts 'xmppd: warning: all streams will be logged in the clear!'
        end

        # Initialize logging.
        $log = MyLog::MyLogger.instance

        if $debug
            $log.xmppd.level = 0
            $log.c2s.level = 0
            $log.s2s.level = 0
        end

        $log.xmppd.unknown '-!- new logging session started -!-'
        $log.c2s.unknown '-!- new logging session started -!-'
        $log.s2s.unknown '-!- new logging session started -!-'

        # Set up listening ports.
        Listen::init
    end

    def ioloop
        loop do
            # Update the current time.
            $time = Time.now.to_f

            # Kill off any dead connections.
            $connections.delete_if { |c| c.dead? }

            if $connections.empty? && $listeners.empty?
                sleep(1)
                next
            end

            readfds = $connections.collect { |c| c.socket }
            readfds += $listeners

            ret = select(readfds, [], [], 1)

            next unless ret
            next if ret[0].empty?

            ret[0].each do |s|
                if s.class == Listen::Listener
                    if s.type == 'client'
                        ns = s.accept
                        nhost = ns.peeraddr[3].sub('::ffff:', '')
                        ncs = XMPP::ClientStream.new(nhost)
                        ncs.socket = ns
                        $connections << ncs
                        ncs.connect
                    else
                        ns = s.accept
                        nhost = ns.peeraddr[3].sub('::ffff:', '')
                        nss = XMPP::ServerStream.new(nhost)
                        nss.socket = ns
                        $connections << nss
                        nss.connect
                    end
                else
                    c = $connections.find { |tc| tc.socket == s }
                    c.read
                end
            end
        end

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
