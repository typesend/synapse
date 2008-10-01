#
# synapse: a small XMPP server
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
require 'xmppd/configure/listen'
require 'xmppd/configure/logging'
require 'xmppd/configure/operator'

module Configure

#
# A singleton class that holds all of our configuration data.
#
class Configuration
    attr_accessor :hosts, :logging, :listen, :auth, :deny, :operator

    def initialize
        @hosts = []
        @logging = Configure::Logging.new
        @listen = Configure::Listen.new
        @auth = []
        @deny = []
        @operator = []
    end
end

end # module Configure
