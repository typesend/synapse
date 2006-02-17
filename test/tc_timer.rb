#
# xmppd: a small XMPP server
# tc_timer.rb: timer testing
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'test/unit'

#
# Import required xmppd modules.
#
require 'xmppd/timer'
require 'xmppd/log'
require 'xmppd/var'

class TestTimer < Test::Unit::TestCase
    @ts = nil
    @tn = nil
    # This just sets up logging for the test.

    def test_1_sulog                         
        assert_nothing_raised do
            $config = Configure::Configuration.new
            $config.logging.enable = false
            $log = MyLog::MyLogger.instance
            $log.xmppd = Logger.new('test/xmppdt.log')
            $log.c2s = Logger.new('test/c2st.log')
            $log.s2s = Logger.new('test/s2st.log')
        end
    end    
       
    def test_z_tdlog
        assert_nothing_raised do
            $log.xmppd.close
            $log.c2s.close
            $log.s2s.close
            
            File.delete('test/xmppdt.log')
            File.delete('test/c2st.log')
            File.delete('test/s2st.log')
        end
    end

    def test_timer
        @ts = Time.now.to_f

        assert_nothing_raised do
            Timer::Timer.new('unit test', 1, true) { timer_callback }
        end
    end

    def timer_callback
        @tn = Time.now.to_f
        delta = @tn - @ts

        assert_true(delta >= 1)
    end
end
