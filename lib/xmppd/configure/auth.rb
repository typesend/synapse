#
# synapse: a small XMPP server
# auth.rb: client authorization configuration
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

module Configure

#
# Represents auth{} configuration data.
#
class Auth
    attr_accessor :host, :match
    attr_reader :timeout, :plain, :legacy_auth

    def initialize
        @host = []
        @match = []
        @timeout = 300
        @plain = false
        @legacy_auth = false
    end

    def timeout=(value)
        unless value.class == Fixnum
            raise ArgumentError, "invalid 'timeout' (must be integer)"
        end

        @timeout = timeout
    end

    def plain=(value)
        unless value == true or value == false
            raise ArgumentError, "invalid 'plain' (must be true/false)"
        end
           
        @plain = value
    end    

    def legacy_auth=(value)
        unless value == true or value == false
            raise ArgumentError, "invalid 'legacy_auth' (must be true/false)"
        end

        @legacy_auth = value
    end
end

end # module Configure
