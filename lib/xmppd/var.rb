#
# xmppd: a small XMPP server
# var.rb: global variables
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

# Version information
require 'xmppd/version'

# The current epoch time.
$time = Time.now.to_f

# Current working directory.
$wd = Dir.getwd
