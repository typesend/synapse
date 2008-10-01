#
# synapse: a small XMPP server
# timers.rb: timed code execution
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# Import required Ruby modules.
#
require 'timeout'

#
# The Timer namespace.
#
module Timer

class Timer
    @@timers = {}

    attr_reader :name, :time, :repeat

    def initialize(name, time, repeat = false, &block)
        @name = name
        @time = time.to_i
        @repeat = repeat
        @block = block

        @@timers['name'] = self

        $log.xmppd.info "new timer: #{@name} every #{@time} secs"

        Thread.new { start }
    end

    ######
    public
    ######

    def timers
        @@timers
    end

    def start
        begin
            Timeout::timeout(@time) { sleep(@time + 1) }
        rescue Timeout::Error
            @block.call
            retry if @repeat
        end
    end
end

end # module Timer
