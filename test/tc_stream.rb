#
# xmppd: a small XMPP server
# tc_stream.rb: XMPP stream testing
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'logger'
require 'socket'
require 'test/unit'

#
# Import required xmppd modules.
#
require 'xmppd/configure'
require 'xmppd/log'
require 'xmppd/var'

require 'xmppd/xmpp/stream'

class TestStream < Test::Unit::TestCase
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

    def test_serverstream
        assert_nothing_raised do
            stream = XMPP::ServerStreamOut.new('malkier.net', 'example.org')
            stream.connect
            stream.close
        end
    end

    def test_clientstream
        assert_nothing_raised do
            stream = XMPP::ClientStream.new('malkier.net')
            stream.socket = TCPSocket.new('malkier.net', 5222)
            stream.connect
            stream.close
        end

        assert_raises(RuntimeError) do
            stream = XMPP::ClientStream.new('malkier.net')
            stream.connect
            stream.close 
        end
    end
end
