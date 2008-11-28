unless defined? IDN

  case RUBY_VERSION.to_f
    when 1.8
      # Check for libidn.
      puts 'using idn gem'
      begin
          require 'idn'
      rescue LoadError
          puts 'xmppd: there was an error loading the IDN library'
          puts "xmppd: chances are you just don't have it"
          puts 'xmppd: gem install --remote idn'
          puts 'xmppd: http://rubyforge.org/projects/idn/'
          puts 'xmppd: you must install libidn for this gem to work'
          puts 'xmppd: http://www.gnu.org/software/libidn/'
          exit
      end    
    when 1.9
      puts "using ruby 1.9 IDN hack. check if it's been released yet?"
    
      module IDN

        class Stringprep

          def self.nameprep string
            res = %x[idn --quiet -p='Nameprep' #{string}].chomp.force_encoding('ascii')
          end

          def self.nodeprep string
            res = %x[idn --quiet -p='Nodeprep' #{string}].chomp.force_encoding('ascii')
          end

          def self.resourceprep string
            res = %x[idn --quiet -p='Resourceprep' #{string}].chomp.force_encoding('ascii')
          end

        end #class

      end #module
    
  end # case

end #unless defined?
