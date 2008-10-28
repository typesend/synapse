#
# synapse: a small XMPP server
# xmpp/parser.rb: parse and do initial XML processing
#
# Copyright (c) 2006-2008 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# The XMPP namespace.
#
module XMPP

#
# The Process namespace.
# This is meant to be a mixin to a Stream.
#
module Process
    
def process_stanza(stanza)
    # Section 11.1 - no 'to' attribute
    #   Server MUST handle directly.
    if not stanza.attributes['to']    
        if server?
            $log.s2s.error "Got bad stanza from #{@host}: " +
                           "'#{stanza.name}' (no 'to' attribute)"

            error('bad-format')
        else
            # Section 11.1.2 - message
            #   Server MUST treat as if 'to' is the bare JID of the sender.
            if stanza.name == 'message'
                stanza.add_attribute('to', @user.jid)
                handle_message(stanza)

            # Section 11.1.3 - presence
            #   Server MUST broadcast according to XMPP-IM.
            elsif stanza.name == 'presence'
                # XXX - 11.1.3 - presence
                handle_presence(stanza)

            # Section 11.1.4 - iq
            #   Server MUST process on behalf of the account that received it.
            elsif stanza.name == 'iq'
                # XXX - 11.1.4 - iq
                handle_iq(stanza)

            # All other recognized stanzas.
            else
                send("handle_#{stanza.name}", stanza)
            end
        end
    else
        # Separate out the JID parts.
        node,   domain   = stanza.attributes['to'].split('@')
        domain         ||= node
        node             = domain ? node : nil
        domain, resource = domain.split('/')

        # Section 11.2 - local domain
        #   Server MUST process
        if $config.hosts.include?(domain)
            # Section 11.2.1 - mere domain
            #   Server MUST handle based on stanza type.
            if not node and not resource
                # XXX - 11.2.1 - mere domain
                send("handle_#{stanza.name}", stanza)
                
            # Section 11.2.2 - domain with resource
            #   Server MUST handle based on stanza type.
            elsif not node and resource
                # XXX - 11.2.2 - domain with resource
                send("handle_#{stanza.name}", stanza)
                
            # Section 11.2.3 - node at domain
            #   Rules defined in XMPP-IM - XXX
            elsif node and domain and not resource
                # XXX - 11.2.3.1 - user not found
                # XXX - 11.2.3.2 - bare jid
                # XXX - 11.2.3.3 - full jid
                # XXX - 11.2.3 - node at domain
                send("handle_#{stanza.name}", stanza)
            end
        # Section 11.3 - foreign domain
        #   Server SHOULD attempt to route.
        else
            # XXX - s2s
            write Stanza.error(stanza, 'FEATURE-NOT-IMPLEMENTED', 'cancel')
        end
    end
end

end # module Process
end # module XMPP