#
# xmppd: a small XMPP server
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
# The XMPP namespace.
#
module XMPP

#
# The Parser namespace.
# This is meant to be a mixin to a Stream.
#
module Parser

def parse
    @current = nil
    saved = ''

    parser = REXML::Parsers::SAX2Parser.new(@recvq)

    parser.listen(:start_element) do |uri, localname, qname, attributes|
        e = REXML::Element.new(qname)
        e.add_attributes(attributes)

        @current = @current.nil? ? e : @current.add_element(e)

        if @current.name == 'stream' and not established?
            handle_stream(@current)
            @current = nil
        end
    end

    parser.listen(:end_element) do |uri, localname, qname|
        if qname == 'stream:stream' and @current.nil?
            close
            return
        end

        unless @current.parent
            methname = "handle_#{@current.name}"
            methname.sub!(':', '_')

            unless respond_to? methname
                if client?
                    $log.c2s.error "Unknown stanza from #{@host}: " +
                                   "'#{current.name}' (no '#{methname}')"
                else
                    $log.s2s.error "Unknown stanza from #{@host}: " +
                                   "'#{current.name}' (no '#{methname}')"
                end

                error('xml-not-well-formed')
                return
            end

            send(methname, @current)
        end

        @current = @current.parent
    end

    parser.listen(:characters) do |text|
        if @current
            rtx = REXML::Text.new(text.to_s, @current.whitespace, nil, true)
            @current.add(rtx)
        end
    end

    parser.listen(:cdata) do |text|
        @current.add(REXML::CData.new(text)) if @current
    end

    begin
        parser.parse
    rescue REXML::ParseException => e
        if e.message =~ /must not be bound/i # REXML bug. Reported.
            str = 'xmlns:xml="http://www.w3.org/XML/1998/namespace"'
            @recvq.gsub!(str, '')
            parse
        else # Probably just an incomplete read(). Store it for next time.
             # ^^^^^^^ <- Gotta figure that out, XXX
            saved = @recvq
        end
    ensure
        @recvq = saved
    end
end

end # module Parser

end # module XMPP
