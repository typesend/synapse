# $Id$

TEST_RUN = true unless defined? TEST_RUN

require 'rubygems'
require 'spec'
#require File.expand_path(
#    File.join(File.dirname(__FILE__), %w[.. lib xmppd]))

$: << File.join(Dir.getwd, 'lib')
$0 = 'xmppd'

# Import required xmppd modules.
require 'xmppd'

Spec::Runner.configure do |config|
  # == Mock Framework
  #
  # RSpec uses it's own mocking framework by default. If you prefer to
  # use mocha, flexmock or RR, uncomment the appropriate line:
  #
  # config.mock_with :mocha
  # config.mock_with :flexmock
  # config.mock_with :rr
  
  config.before(:all) do
   timed_cycle
   setup_config
  end
  
end

def setup_config
  $config = Configure::Configuration.new
  $config.hosts << 'example.org'
  $config.hosts << 'example.com'
  $config.hosts << 'example.net'
  $config.logging.enable = false
  $log = MyLog::MyLogger.instance
  $log.xmppd = Logger.new('var/test/xmppdt.log')
  $log.c2s = Logger.new('var/test/c2st.log')
  $log.s2s = Logger.new('var/test/s2st.log')
end

def cycle_database
  puts '###'
  puts 'CYCLING DATABASE'
  puts '###'
  
  #db reset code here

end

def timed_cycle
  # cycle database every 5 minutes
  unless defined? $LAST_CYCLE
    $LAST_CYCLE = Time.now
    puts '### reset cycle ###'
  end

  if (Time.now - $LAST_CYCLE) > 300
    cycle_database
    $LAST_CYCLE = Time.now
    puts '### reset cycle ###'
  end
end



# EOF
