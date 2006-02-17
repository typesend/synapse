#
# xmppd: a small XMPP server
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

class TestDB < Test::Unit::TestCase
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
end
