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

class REXML::Source
    def buffer=(string)
        @buffer ||= ''
        @buffer += string

        # A megabyte in the buffer.
        raise XMPP::Parser::ParserError if @buffer.length > (1024*1024)
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
    @rtime = Time.now.to_f
    methname = "handle_#{stanza.name}"
    methname.sub!(':', '_')

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

    @parser = REXML::Parsers::SAX2Parser.new(@recvq)

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

def parse
    begin
        @parser.source.buffer = @recvq
        @parser.parse

        raise ParserError if @current.to_s.length > (1024*1024)
    rescue ParserError
        # If we get here, they've maxed out on their buffer.
        error('policy-violation', "recvq exceeded: #{@current.to_s.length}")
    rescue REXML::ParseException => e
        if e.message =~ /must not be bound/i # REXML bug. Reported.
            str = 'xmlns:xml="http://www.w3.org/XML/1998/namespace"'
            @recvq.gsub!(str, '')
            retry
        else
            # REXML throws this when it gets a partial stanza that's not
            # well-formed. We store it in the buffer for the next read(),
            # XXX: IF I DO THIS, THERE IS NO WAY TO DETECT INVALID
            # XML IN THE STREAM. IF THIS CLIENT IS MESSING WITH US,
            # IT WILL SIT THERE UNTIL IT TIMES OUT, BEING USELESS.
        end
    end

    @recvq = ''
end

end # module Parser

end # module XMPP
