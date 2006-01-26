#
# xmppd: a small XMPP server
# Rakefile: Ruby Makefile
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#
 
#
# Import required Ruby modules.
#
require 'rubygems'

require 'rake/clean'
require 'rake/gempackagetask'
require 'rake/packagetask'
require 'rake/rdoctask'
require 'rake/testtask'

#
# Import required xmppd modules.
#
require 'lib/xmppd/version'

# Make output unbuffered.
$stdout.sync = true

#
# Default task.
#
# $ rake
#
task :default => [:test]

task :test do
    print '>>> nothing to test yet'
end

#
# Subversion stuff.
#
# $ rake commit
#
desc 'Commit current working copy'
task :commit => [:clobber, :test] do
    sh 'svn log -vrHEAD:1 > ChangeLog'
    sh 'svn commit --editor-cmd=vi'   
end

#
# Makes a new release. Checks, clobbers, tests, versions, and packages.
#
desc 'Make a new release'
task :release => [:prerelease, :clobber, :test, :update_version, :package]

task :prerelease => [:check_ver, :check_commit]

task :check_ver do
    print '>>> checking that you provided a version number... '
                                                               
    unless ENV['VER']                                          
        puts 'no'
        puts 'Usage: rake <task> VER=x.y'
        exit
    else    
        puts ENV['VER']
    end                
end

task :check_commit do
    print '>>> checking that working copy is in sync... '      
 
    unless `svn status`.empty?
        puts 'no'
        puts "You need to `rake commit' first."
        exit
    else
        puts 'yes'
    end
end

task :update_version => [:check_ver] do
    print '>>> updating version... '

    t = Time.now

    release_date = '%s-%s-%s' % [t.year.to_s, t.month.to_s, t.day.to_s]
    svn_version = 'r' << `svnversion -n .`

    open('lib/xmppd/version.rb', 'w') do |f|
        f.puts '#'
        f.puts '# xmppd: a small XMPP server'
        f.puts '# version.rb: dynamically-generated version information'
        f.puts '#'
        f.puts '# Copyright (c) 2006 Eric Will <rakaur@malkier.net>'
        f.puts '#'
        f.puts '# $Id$'
        f.puts '#'
        f.puts
        f.puts "$version = '%s'" % ENV['VER']
        f.puts "$release_date = '%s'" % release_date
        f.puts "$svn_version = '%s'" % svn_version
    end

    puts '%s (%s)' % [ENV['VER'], svn_version]
end
#
# Documentation generation.
#
# $ rake rdoc
#
Rake::RDocTask.new do |r|
    r.rdoc_dir = 'doc'
    r.options << '--line-numbers' << '--inline-source'
    r.rdoc_files.include('lib/**/*')
end

#
# Package generation.
#
# $ rake package
#
PKG_FILES = FileList['Rakefile', 'ChangeLog',
                     'bin/*', 'etc/*',
                     'lib/**/*',
                     'test/**/*.rb']

# Makes .tar.gz and .zip packages.
Rake::PackageTask.new('package') do |p|
    p.name = 'xmppd'
    p.version = ENV['VER'] || $version
    p.need_tar = true
    p.need_zip = true
    p.package_files = PKG_FILES
end

spec = Gem::Specification.new do |s|
    s.name = 'xmppd'
    s.version = ENV['VER'] || $version
    s.author = 'Eric Will'
    s.email = 'rakaur@malkier.net'
    s.homepage = 'http://xmppd.malkier.net/'
    s.platform = Gem::Platform::RUBY
    s.summary = 'a small, lightweight XMPP server'
    s.files = PKG_FILES.to_a
    s.require_paths = ['lib']

    #s.test_file = 'test/ts_xmppd.rb'
    s.has_rdoc = true

    s.rubyforge_project = 'xmppd'

    s.default_executable = 'xmppd'
    s.executables = ['xmppd']

    s.add_dependency('idn', '>= 0.0.1')
end

# Makes a .gem package.
Rake::GemPackageTask.new(spec) do
end
