#
# xmppd: a small XMPP server
# tc_config.rb: configure testing
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
require 'xmppd/configure'
require 'xmppd/var'

class TestConfig < Test::Unit::TestCase
    def test_ok
        assert_nothing_raised do
            Configure.load('test/ok_config.xml')
        end

        assert($config.class == Configure::Configuration,
               "$config should be there")

        assert($config.listen.length == 2, "should be two listens")

        assert($config.listen[1].s2s.length == 2,
               "second listen should have two s2s")

        assert($config.operator[0].jid[0] == 'unit@test',
               "operator jid should be 'unit@test'")
    end

    def test_bad
        assert_raises(Configure::ConfigureError) do
            Configure.load('test/bad_config.xml')
        end
    end
end
