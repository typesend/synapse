#
# synapse: a small XMPP server
# base64.rb: quick hack for ruby1.9
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# This is just here for Ruby 1.9, as it doesn't
# have a 'base64' module. I'll eventually do this
# in a better way.
#
module Base64

extend self

def encode64(string)
    [string].pack('m')
end

def decode64(string)
    string.unpack('m')[0]
end

end # module Base64
