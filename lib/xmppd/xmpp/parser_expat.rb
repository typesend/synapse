#
# synapse: a small XMPP server
# xmpp/parser_expat.rb: parse and do initial XML processing using expat
#
# Copyright (c) 2006-2008 Eric Will <rakaur@malkier.net>
#

#
# Import required Ruby modules.
#
require 'xmlparser'
require 'rexml/document'

#
# Import required xmppd modules.
#
require 'xmppd/var'
require 'xmppd/xmpp'

#
# The XMPP namespace.
#
module XMPP

#
# The Parser namespace.
# This is meant to be a mixin to a Stream.
#
module Parser

class ParserError < Exception
end

# XXX - future site of stanza rule processing a la #60.
def dispatch(stanza)
    # Do flood checks.
    return if @flood['killed']

    # Reset the timer if they're below the rate limits.
    if ($time - @flood['mtime']) > 10 or not message_ready?
        @flood['mtime']   = $time
        @flood['stanzas'] = 0
    end

    @flood['stanzas'] += 1 # This stanza counts.

    # 30 stanzas in 10 seconds, outside of setup...
    if @flood['stanzas'] > 30 and message_ready?
        @flood['killed'] = true
        error('policy-violation', { 'name' => 'rate-limit-exceeded',
                                    'text' => '>30 stanzas in <10 seconds' })

        return
    end unless @resource.user.operator? if @resource

    methname = "handle_#{stanza.name}"

    unless respond_to?(methname)
        if client?
            $log.c2s.error "Unknown stanza from #{@host}: " +
                           "'#{stanza.name}' (no '#{methname}')"
        else
            $log.s2s.error "Unknown stanza from #{@host}: " +
                           "'#{stanza.name}' (no '#{methname}')"
        end

        error('invalid-namespace')
    else
        send(methname, stanza)
    end
end

def parser_initialize
    @current = nil
    @parser  = XMLParser.new
end

def parse(data)
    @parser = XMLParser.new if not established?
    
    begin
        @parser.parse(data, false) do |args|
            type, name, data = args
            
            case type
            when :START_ELEM
                e = REXML::Element.new(name)
                e.add_attributes(data)
                
                @current = @current.nil? ? e : @current.add_element(e)
                
                if @current.name == 'stream' and not established?
                    handle_stream(@current)
                    @current = nil
                end
            when :END_ELEM
                if name == 'stream:stream' and @current.nil?
                    close
                else
                    dispatch(@current) unless @current.parent
                    @current = @current.parent
                end
            when :CDATA
                next if data.gsub(/\s/, '').empty?
                
                if @current
                    rtx = REXML::Text.new(data, @current.whitespace, nil, true)
                    @current.add(rtx)
                end
            end
        end
                    
        raise ParserError if @current.to_s.length > 65536
    rescue ParserError
        error('policy-violation', { 'name' => 'stanza-too-big',
                                    'text' => 65536 })
    rescue XMLParserError => e
        # expat never does this. The RFC wants us to be able to stitch together
        # partial stanzas and also to detect invalid XML, but it's
        # pretty much IMPOSSIBLE to do both. REXML meets half way by stitching
        # together well-formed partial stanzas, and doing a stream error
        # on anything not well-formed. expat can't do that, though, so it'll
        # just sit there on not-well-formed stanzas until the buffer maxes out.
        
        error('xml-not-well-formed')
    end
end

end # module Parser
end # module XMPP
