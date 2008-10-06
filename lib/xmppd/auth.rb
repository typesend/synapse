#
# synapse: a small XMPP server
# auth.rb: handles authorization
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'rexml/document'

#
# Import required xmppd modules.
#
require 'xmppd/var'

# The Auth namespace.
module Auth

extend self

#
# See if host is authorized.
#
def check(host)
    # First check to see whether they match any auths.
    auth = check_auth(host)
    return false unless auth

    # Now see if they match a deny.
    return false if check_deny(host)

    # If we get here then we passed.
    return auth
end

def check_auth(host)
    m = nil

    $config.auth.each do |auth|
        return auth if auth.host.include?(host)

        m = auth.match.find { |a| host =~ a }

        return auth if m
    end

    return false
end

def check_deny(host)
    m = nil

    $config.deny.each do |deny|
        return true if deny.host.include?(host)

        m = deny.match.find { |a| host =~ a }

        return true if m
    end

    return false
end

end # module Auth
