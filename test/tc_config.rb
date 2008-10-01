#
# synapse: a small XMPP server
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

class TestParser < Configure::Parser
    def handle_section(entry)
    end
end

class TestConfig < Test::Unit::TestCase
    def test_parser
        data = <<-EOT
            section "section_data"
            {
                section_var = "var_data";

                subsection = { blah; blah2; };
            };
        EOT

        parser, trie = nil, nil

        assert_nothing_raised do
            parser = TestParser.new
            parser.feed(data)
            trie = parser.parse
        end

        assert(trie.length > 0, "parse trie shouldn't be empty")
        assert_equal(1, trie.length)

        assert_equal('section', trie[0].name)
        assert_equal('section_data', trie[0].data)

        var = nil
        trie[0].entries.each do |entry|
            var = entry if entry.name == 'section_var'
        end

        assert_not_nil(var)
        assert_equal('var_data', var.data)

        var = nil
        trie[0].entries.each do |entry|
            var = entry if entry.name = 'subsection'
        end

        assert_not_nil(var)

        var.entries.each do |entry|
            assert_nil(entry.data)
            assert(entry.entries.empty?)
        end
    end

    def test_no_section_name
        data = <<-EOT
            {
                var = "data";
            };
        EOT

        assert_raise(Configure::ConfigError) do
            parser = TestParser.new
            parser.feed(data)
            parser.parse
        end
    end

    def test_missing_semicolon
        data = <<-EOT
            section
            {
                var = "data"
            };
        EOT

        assert_raise(Configure::ConfigError) do
            parser = TestParser.new
            parser.feed(data)
            parser.parse
        end
    end

    def test_comments
        data = <<-EOT
            \#section
            //{
            \#    var;
            //};
        EOT

        parser, trie = nil, nil

        assert_nothing_raised do
            parser = TestParser.new
            parser.feed(data)
            trie = parser.parse
        end

        assert(trie.empty?, 'trie should be empty')
    end

    def test_config
        config = Configure::Configuration.new

        config.hosts << "example.com" << "example.net" << "example.org"

        assert_equal(3, config.hosts.length)
        assert_nil(config.logging.level, 'config.logging.level should be nil')
    end

    def test_config_logging
        log = nil
        assert_nothing_raised { log = Configure::Logging.new }

        assert_raises(ArgumentError) { log.level = 'invalid' }

        assert_nothing_raised { log.level = 'debug' }
        assert_nothing_raised { log.xmppd = 'valid/path.log' }
        assert_nothing_raised { log.c2s = 'valid/path.log' }
        assert_nothing_raised { log.s2s = 'valid/path.log' }
    end

    def test_config_listen
        listen = nil
        assert_nothing_raised { listen = Configure::Listen.new }

        entry = { 'host' => '*', 'port' => 5222 }
        assert_nothing_raised { listen.c2s << entry }
    end

    def test_auth
        auth = nil
        assert_nothing_raised { auth = Configure::Auth.new }

        assert_raises(ArgumentError) { auth.plain = 'invalid' }
        assert_raises(ArgumentError) { auth.legacy_auth = 'invalid' }

        assert_nothing_raised { auth.plain = true }
        assert_nothing_raised { auth.legacy_auth = false }
        assert_nothing_raised { auth.host << "127.0.0.1" }
    end

    def test_deny
        deny = nil
        assert_nothing_raised { deny = Configure::Deny.new }

        assert_nothing_raised { deny.host << "127.0.0.1" }
    end

    def test_operator
        oper = nil
        assert_nothing_raised { oper = Configure::Operator.new }

        assert_raises(ArgumentError) { oper.jid = 'invalid' }
        assert_raises(ArgumentError) { oper.announce = 'invalid' }

        assert_nothing_raised { oper.jid = 'unit@test' }
        assert_nothing_raised { oper.announce = false }
    end
end
