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

#
# Yes I know, global variables are evil, whatever. I thought about moving
# these to be class variables of XMPPd but I just really don't care.
#

# A singleton instance of Configure::Configuration.
$config = nil

# Our configuration file.
$config_file = 'etc/xmppd.conf'

# List of active connections.
$connections = []

# Debug mode?
$debug = false

# Fork into the background?
$fork = true

# List of listening sockets.
$listeners = []

# Logger.
$log = nil

# The current epoch time.
$time = Time.now.to_f

# Current working directory.
$wd = Dir.getwd