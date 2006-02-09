#
# xmppd: a small XMPP server
# xmpp/client.rb: handles clients
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'idn'
require 'rexml/document'

#
# Import required xmppd modules.
#
require 'xmppd/var'

#
# The XMPP namespace.
#
module XMPP

#
# The Client namespace.
# This is meant to be a mixin to a Stream.
#
module Client

def handle_stream(elem)
    # First verify namespaces.
    unless elem.attributes['stream'] == 'http://etherx.jabber.org/streams'
        error('invalid-namespace')
        return
    end

    unless elem.attributes['xmlns'] == 'jabber:client'
        error('invalid-namespace')
        return
    end

    # Verify hostname.
    unless elem.attributes['to']
        error('bad-format')
        return
    end

    begin
        to_host = IDN::Stringprep.nameprep(elem.attributes['to'])
    rescue Exception
        error('bad-format')
        return
    end

    m = $config.hosts.find { |h| h == to_host }

    unless m
        error('host-unknown')
        return
    end

    @myhost = to_host

    # Seems to have passed all the requirements.
    establish

    # XXX - remove this when we do more work
    error('internal-server-error')
end


end # module Client
end # module XMPP
