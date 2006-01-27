#
# xmppd: a small XMPP server
# configuration.rb: configuration settings
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required xmppd modules.
#
require 'xmppd/configure/auth'
require 'xmppd/configure/configuration'
require 'xmppd/configure/listen'
require 'xmppd/configure/logging'
require 'xmppd/configure/operator'

module Configure

#
# A singleton class that holds all of our configuration data.
#
class Configuration
    attr_accessor :virtual_host, :logging, :listen, :auth, :operator

    def initialize
        @virtual_host = []
        @logging = Configure::Logging.new
        @listen = []
        @auth = []
        @operator = []
    end
end

end # module Configure
