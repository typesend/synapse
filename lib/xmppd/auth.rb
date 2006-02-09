#
# xmppd: a small XMPP server
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
    return false unless check_auth(host)

    # Now see if they match a deny.
    return false if check_deny(host)

    # If we get here then we passed.
    return true
end

def check_auth(host)
    m = nil

    $config.auth.each do |auth|
        m = auth.host.find { |h| h == host }

        return true if m

        m = auth.match.find { |a| host =~ a }

        return true if m
    end

    return false
end

def check_deny(host)
    m = nil

    $config.deny.each do |deny|
        m = deny.host.find { |h| h == host }

        return true if m

        m = deny.match.find { |a| host =~ a }

        return true if m
    end

    return false
end

end # module Auth
