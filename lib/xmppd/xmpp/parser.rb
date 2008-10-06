#
# synapse: a small XMPP server
# xmpp/parser.rb: parses XML
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
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
require 'xmppd/xmpp/stream'

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

def dispatch(stanza)
    # Do flood checks.
    # XXX - opers excluded.
    return if @flood['killed']

    # Reset the timer if they're below the rate limits.
    if ($time - @flood['mtime']) > 10 or not established?
        @flood['mtime']   = $time
        @flood['stanzas'] = 0
    end

    @flood['stanzas'] += 1 # This stanza counts.

    # 30 stanzas in 10 seconds, outside of setup...
    if @flood['stanzas'] > 30 and established?
        @flood['killed'] = true
        error('policy-violation', { 'name' => 'rate-limit-exceeded',
                                    'text' => '>30 stanzas in <10 seconds' })

        return
    end

    methname = "handle_#{stanza.name}"

    unless respond_to? methname
        if client?
            $log.c2s.error "Unknown stanza from #{@host}: " +
                           "'#{stanza.name}' (no '#{methname}')"
        else
            $log.s2s.error "Unknown stanza from #{@host}: " +
                           "'#{stanza.name}' (no '#{methname}')"
        end

        error('xml-not-well-formed')
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
            # well-formed. We store it in the buffer for the next read(),
            # XXX: IF I DO THIS, THERE IS NO WAY TO DETECT INVALID
            # XML IN THE STREAM. IF THIS CLIENT IS MESSING WITH US,
            # IT WILL SIT THERE UNTIL IT TIMES OUT, BEING USELESS.
            error('xml-not-well-formed')
        end
    end
end

end # module Parser
end # module XMPP
