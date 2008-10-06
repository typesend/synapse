#
# synapse: a small XMPP server
# timers.rb: timed code execution
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

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

        @@timers[name] = self

        $log.xmppd.info "new timer: #{@name} every #{@time} secs"

        Thread.new { start }
    end

    ######
    public
    ######

    def timers
        @@timers
    end

    def delete(name)
        if @@timers[name]
            @@timers.delete name
            $log.xmppd.info "timer deleted: #{name}"
        end
    end

    def start
        loop do
            sleep(@time)
            $log.xmppd.debug "executing timer: #{@name}"
            @block.call
            break unless @repeat
        end

        $log.xmppd.info "timer expired: #{@name}"
    end
end

end # module Timer
