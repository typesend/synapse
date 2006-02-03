#
# xmppd: a small XMPP server
# configure/parser.rb: bind-style configuration file parser
#
# Copyright (c) 2004-2005 Eric Will <rakaur@malkier.net>
#
# $Id$
#

module Configure

#
# Exception raised when there's a problem with the parser.
#
class ConfigError < Exception
end

#
# Class used to build the trie structure.
#
class Entry
    attr_accessor :name, :data, :line, :prevlev, :entries

    def initialize
        @name = nil
        @data = nil
        @line = nil
        @prevlev = nil
        @entries = []
    end
end

#
# = Configure::Parser -- BIND-style configuration file parser
#
# == Introduction
#
# Most IRC programs tend to use a named.conf-like configuration file
# format these days. Being a good IRC developer, I used the same parser
# everyone else used: configparse.c from csircd. When I started coding
# in Python, I decided to write me own. Not knowing anything about
# lexers (I still don't) I just wrote it out by parsing it one character
# at a time. When I started coding in Ruby, I had to do it all over
# again. I'm glad to say this one is slightly more usable than my
# Python hack.
#
#
# == Credits
#
# The original parser was written in C by comstud for csircd.
# Copyright (c) 1999-2004 csircd development team
#
# The PHP parser was written by Matt Lanigan for an IRC bot.
# Copyright (c) 2004 Matt Lanigan <rintaun@projectxero.net>
#
# The Python parser was written by me for a few IRC programs.
# Copyright (c) 2004 Eric Will <rakaur@malkier.net>
#
#
# == Author
#
# The Ruby parser was written by me for an IRC services program.
# Copyright (c) 2004-2006 Eric Will <rakaur@malkier.net>
#
# ----
#
# = Usage
#
# Usage is about as easy as it gets for a generic configuration parser.
#
#
# == How It Works
#
# The parser takes a string of data that resembles named.conf and
# translates it into a trie of Configure::Entrys. That is, this:
#
#    section "name" {
#        key "value";
#    };
#
# Would be turned into this:
#
#    trie[ Configure::Entry { 'name'    => 'section',
#                          'data'    => 'name',
#                          'line'    => 3,
#                          'entries' => [ Configure::Entry { 'name'    => 'key',
#                                                         'data'    => 'value',
#                                                         'line'    => 2,
#                                                         'entries' => [] }
#                                       ]
#          }
#    ]
#
# After all the parsing is done we get a spanning trie of these. The
# parser then goes through all of the nodes on the base trie and
# calls handler functions based on their names. In this case,
# +handle_section+ would be called and would be passed the first (and
# only) node in the trie. It's up to +handle_section+ to dispatch
# this out to more specialized handler functions in the same way that
# the parser dispatches the base nodes.
#
#
# == Notes
#
# In addition to the named.conf syntax, you can also use an equals sign
# ('=') to seperate key from value.
#
# Shell style ('#') and C++ style ('//') comments are ignored. C style
# ('/* ... */') comments are not implemented.
#
#
# == How To Use It
#
# Following on from the above example, we'd want to do something like
# this:
#
#    class MyParser < Configure::Parser
#        def initialize
#            super
#        end
#
#        def handle_section(entry)
#            entry.entries.each do |node|
#                methname = 'handle_section_%s' % node.name
#
#                if respond_to? methname
#                    send(methname, node)
#                else
#                    unknown_directive(node.name, node.line)
#                end
#            end
#        end
#
#        def handle_section_key(entry)
#            missing_parameter(entry.name, entry.line) unless entry.data
#
#            entry.data == 'value' # => true
#        end
#    end
#
#    parser = MyParser.new
#    parser.feed(somedata)
#    parser.parse
#
# Of course, you don't *have* to dispatch them like I showed in the
# example, you but different settings sometimes need different
# operations performed on them before they're used (such as +to_i+)
# so I tend to stick with this example.
#

class Parser
    def initialize
        @data = ''
    end

    #
    # You can call this as many times as you want; all it does is
    # keep adding to the data to be parsed without actually parsing it.
    #
    def feed(data)
        @data << data
    end

    #
    # Does all the hard, grimy work of parsing the data into a trie
    # of Configure::Entrys and calling handlers based on the trie structure.
    #
    def parse
        trie = []
        current_section = Configure::Entry.new
        current_entry = Configure::Entry.new
        line = 1

        in_quote = false
        quote_start = 0

        in_unquote = false
        unquote_start = 0
        unquote_break = false

        in_comment = false

        # Ruby's retarded string methods give me useless ASCII codes.
        class << @data
            def each_chr_with_index
                i = 0

                each_byte do |x|
                    yield x.chr, i
                    i += 1
                end
            end
        end

        @data.each_chr_with_index do |x, i|
            if x == "\n"
                line += 1

                in_comment = false if in_comment
                unquote_break = true unless unquote_break

                if in_quote
                    raise ConfigError, "line #{line}: unterminated string"
                end

            elsif in_comment
                next

            elsif x == '#'
                next if in_quote
                in_comment = true

            elsif x == '/'
                next if in_quote
                in_comment = true if @data[i - 1].chr == '/'

            elsif x == ';'
                next if in_quote

                if in_unquote
                    in_unquote = false
                    unquote_break = false

                    if current_entry.name
                        current_entry.data = @data[unquote_start...i]
                    else
                        current_entry.name = @data[unquote_start...i]
                        current_entry.line = line
                    end

                    unquote_start = 0
                end

                next unless current_entry.name

                current_entry.data.strip! if current_entry.data
                current_entry.name.strip! 
                current_entry.line = line

                unless current_section.name
                    trie << current_entry
                else
                    current_section.entries << current_entry
                end

                current_entry = Configure::Entry.new

            elsif x == '{'
                next if in_quote or in_unquote

                unless current_entry.name
                    raise ConfigError, "line #{line}: no name for section start"
                end

                next if current_section.name and not current_entry.name

                if current_section.name
                    if current_section != current_entry
                        current_entry.prevlev = current_section
                    end
                end

                current_section = current_entry
                current_entry = Configure::Entry.new

            elsif x == '}'
                next if in_quote or in_unquote

                if current_entry.name
                    raise ConfigError, "line #{line}: missing `;' before `}'"
                end

                next unless current_section.name

                current_entry = current_section

                if current_section.prevlev
                    current_section = current_section.prevlev
                else
                    current_section = Configure::Entry.new
                end

            elsif x == '"'
                next if in_unquote

                if in_quote
                    in_quote = false

                    if current_entry.name
                        current_entry.data = @data[quote_start...i]
                    else
                        current_entry.name = @data[quote_start...i]
                        current_entry.line = line
                    end

                    quote_start = 0
                else
                    in_quote = true
                    quote_start = i + 1
                end

            elsif x =~ /\s|=/
                unquote_break = true

            else
                next if in_quote

                unless in_unquote
                    in_unquote = true
                    unquote_break = false
                    unquote_start = i
                end
            end

            if in_unquote and unquote_break
                in_unquote = false
                unquote_break = false

                if current_entry.name
                    current_entry.data = @data[unquote_start...i]
                else
                    current_entry.name = @data[unquote_start...i]
                    current_entry.line = line
                end

                unquote_start = 0
            end
        end

        trie.each do |entry|
            methname = 'handle_%s' % entry.name
    
            if respond_to? methname
                send(methname, entry)
            else
                unknown_directive(entry.name, entry.line)
            end 
        end

    end # def parse

    #########
    protected
    #########

    #
    # Called to report an error for a key that requires a value.
    #
    def missing_parameter(name, line)
        string = "line #{line}: missing parameter for `#{name}'"
        raise Configure::ConfigError, string
    end                                          
       
    #
    # Called to report something in the trie that doesn't have an
    # associated handler method.
    #
    def unknown_directive(name, line)
        string = "line #{line}: unknown configuration directive `#{name}'"
        raise Configure::ConfigError, string
    end 

end # class Parser

end # module Configure
