#
# synapse: a small XMPP server
# tc_logging.rb: logging testing
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'logger'
require 'test/unit'

#
# Import required xmppd modules.
#
require 'xmppd/log'
require 'xmppd/var'

class TestLog < Test::Unit::TestCase
    def test_log
        xmppdt = 'test/xmppt.log'
        c2st = 'test/c2st.log'
        s2st = 'test/s2st.log'

        assert_nothing_raised do
            @xmppd = Logger.new(xmppdt)
            @c2s = Logger.new(c2st)
            @s2s = Logger.new(s2st)
        end

        assert_nothing_raised do
            @xmppd.fatal 'some fatal error'
            @xmppd.error 'some error'
            @xmppd.warn 'some warning'
            @xmppd.info 'some info'
            @xmppd.debug 'some debug info'
            @xmppd.unknown 'some important info'
        end

        assert_nothing_raised do
            @c2s.fatal 'some fatal error'
            @c2s.error 'some error'
            @c2s.warn 'some warning'
            @c2s.info 'some info'
            @c2s.debug 'some debug info'
            @c2s.unknown 'some important info'
        end 

        assert_nothing_raised do
            @s2s.fatal 'some fatal error'
            @s2s.error 'some error'
            @s2s.warn 'some warning'
            @s2s.info 'some info'
            @s2s.debug 'some debug info'
            @s2s.unknown 'some important info'
        end 

        assert_nothing_raised do
            @xmppd.close
            @c2s.close
            @s2s.close
        end

        assert_nothing_raised do
            File.delete(xmppdt)
            File.delete(c2st)
            File.delete(s2st)
        end
    end
end
