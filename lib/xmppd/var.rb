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

# A singleton instance of Configure::Configuration.
$config = nil

# Our configuration file.
$config_file = 'etc/configure.xml'

# Fork into the background?
$fork = false

# Logger.
$log = nil

# The current epoch time.
$time = Time.now.to_f

# Current working directory.
$wd = Dir.getwd
