#
# synapse: a small XMPP server
# db.rb: database configuration
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

module Configure

#
# Represents db{} configuration data.
#
class DB < Hash
    attr_accessor :db_adaptor, :class_name

    def initialize
        @db_adaptor = ''
        @class_name = ''
    end
    
end

end # module Configure