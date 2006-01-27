#
# xmppd: a small XMPP server
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
        generalt = 'test/generalt.log'
        c2st = 'test/c2st.log'
        s2st = 'test/s2st.log'

        assert_nothing_raised do
            @general = Logger.new(generalt)
            @c2s = Logger.new(c2st)
            @s2s = Logger.new(s2st)
        end

        assert_nothing_raised do
            @general.fatal 'some fatal error'
            @general.error 'some error'
            @general.warn 'some warning'
            @general.info 'some info'
            @general.debug 'some debug info'
            @general.unknown 'some important info'
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
            @general.close
            @c2s.close
            @s2s.close
        end

        assert_nothing_raised do
            File.delete(generalt)
            File.delete(c2st)
            File.delete(s2st)
        end
    end
end
