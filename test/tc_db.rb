#
# synapse: a small XMPP server
# tc_db.rb: database testing
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'digest/md5'
require 'test/unit'

#
# Import required xmppd modules.
#
require 'xmppd/db'
require 'xmppd/log'

class TestDB < Test::Unit::TestCase
    # This just sets up logging for the test.
    def setup
        assert_nothing_raised do
            $config = Configure::Configuration.new
            $config.logging.enable = false
            $log = MyLog::MyLogger.instance
            $log.xmppd = Logger.new('test/xmppdt.log')
            $log.c2s = Logger.new('test/c2st.log')
            $log.s2s = Logger.new('test/s2st.log')
        end
    end

    def teardown
        assert_nothing_raised do
            $log.xmppd.close
            $log.c2s.close
            $log.s2s.close

            File.delete('test/xmppdt.log')
            File.delete('test/c2st.log')
            File.delete('test/s2st.log')
        end
    end

    def test_newuser
        newuser = nil

        assert_nothing_raised do
            newuser = DB::User.new('unit', 'example.org', 'secret')
        end

        assert_equal('unit@example.org', newuser.jid)
        assert_equal(newuser, DB::User.users['unit@example.org'])

        passwd = Digest::MD5.digest('unit:example.org:secret')
        assert_equal(passwd, newuser.password)
    end

    def test_dupeuser
        newuser = nil

        assert_nothing_raised do
            newuser = DB::User.new('test', 'example.net', 'secret')
        end

        assert_raises(DB::DBError) do
            newuser = DB::User.new('test', 'example.net', 'secret')
        end
    end

    def test_delete_exist
        newuser = nil

        assert_nothing_raised do
            newuser = DB::User.new('unit', 'example.com', 'secret')
        end

        assert_nothing_raised do
            DB::User.delete(newuser.jid)
        end

        assert_nil(DB::User.users['unit@example.com'])
    end

    def test_delete_nonexist
        assert_raises(DB::DBError) do
            DB::User.delete('doesnt_exist@example.com')
        end

        assert_nil(DB::User.users['doesnt_exist@example.com'])
    end

    def test_userauth
        newuser = nil
        assert_nothing_raised do
            newuser = DB::User.new('unit_test', 'example.org', 'secret')
        end

        auth = DB::User.auth('unit_test@example.org', 'secret', true)
        assert_equal(true, auth)

        auth = DB::User.auth('doesnt_exist@example.org', 'fake', true)
        assert_equal(false, auth)

        auth = DB::User.auth('unit_test@example.org', 'wrong', true)
        assert_equal(false, auth)

        saslpass = Digest::MD5.digest('unit_test:example.org:secret')
        auth = DB::User.auth('unit_test@example.org', saslpass)
        assert_equal(true, auth)

        saslpass = Digest::MD5.digest('doesnt_exist:example.org:fake')
        auth = DB::User.auth('doesnt_exist@example.org', saslpass)
        assert_equal(false, auth)

        saslpass = Digest::MD5.digest('unit_test:example.org:wrong')
        auth = DB::User.auth('unit_test@example.org', saslpass)
        assert_equal(false, auth)
    end
end
