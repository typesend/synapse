#
# synapse: a small XMPP server
# xmpp/parser.rb: parse and do initial XML processing
#
# Copyright (c) 2006-2008 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'rexml/document'
require 'rexml/parsers/sax2parser'

#
# Import required xmppd modules.
#
require 'xmppd/var'
require 'xmppd/xmpp'

#
# This is kind of a hack.
# There's no way to change any of REXML's parser's sources, which
# I kind of need to do so I don't have to run this for every stanza.
#
class REXML::Source
    def buffer=(string)
        @buffer ||= ''
        @buffer  += string

        # 64kb in the buffer. This should never happen.
        raise XMPP::Parser::ParserError if @buffer.length > 65536
    end
end

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
    @parser  = REXML::Parsers::SAX2Parser.new('')

    @parser.listen(:start_element) do |uri, localname, qname, attributes|
        e = REXML::Element.new(qname)
        e.add_attributes(attributes)

        @current = @current.nil? ? e : @current.add_element(e)

        if @current.name == 'stream' and not established?
            handle_stream(@current)
            @current = nil
        end
    end

    @parser.listen(:end_element) do |uri, localname, qname|
        if qname == 'stream:stream' and @current.nil?
            close
        else
            dispatch(@current) unless @current.parent
            @current = @current.parent
        end
    end

    @parser.listen(:characters) do |text|
        if @current
            rtx = REXML::Text.new(text.to_s, @current.whitespace, nil, true)
            @current.add(rtx)
        end
    end

    @parser.listen(:cdata) do |text|
        @current.add(REXML::CData.new(text)) if @current
    end
end

def parse(data)
    begin
        @parser.source.buffer = data
        @parser.parse

        raise ParserError if @current.to_s.length > 65536
    rescue ParserError
        error('policy-violation', { 'name' => 'stanza-too-big',
                                    'text' => 65536 })
    rescue REXML::ParseException => e
        if e.message =~ /must not be bound/i # REXML bug. Reported.
            str = 'xmlns:xml="http://www.w3.org/XML/1998/namespace"'
            data.gsub!(str, '')
            retry
        else
            # REXML throws this when it gets a partial stanza that's not
            # well-formed. The RFC wants us to be able to stitch together
            # partial stanzas and also to detect invalid XML, but it's
            # pretty much IMPOSSIBLE to do both. We meet half way by stitching
            # together well-formed partial stanzas, and doing a stream error
            # on anything not well-formed.
            error('xml-not-well-formed')
        end
    end
end

end # module Parser
end # module XMPP
