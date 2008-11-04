#
# synapse: a small XMPP server
# xmpp/parser.rb: parse and do initial XML processing
#
# Copyright (c) 2006-2008 Eric Will <rakaur@malkier.net>
#

begin
    require 'xmppd/xmpp/parser_expat'
rescue Exception
    require 'xmppd/xmpp/parser_rexml'
end
