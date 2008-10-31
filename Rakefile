#
# synapse: a small XMPP server
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

Rake::TestTask.new do |t|
    t.libs << 'test'
    t.test_files = ['test/ts_xmppd.rb']
end

#
# git stuff.
#
# $ rake push
#
desc 'Push current repository to git origin'
task :push => [:check_commit] do
    sh 'git push origin master'
end

#
# $ rake commit
#
desc 'Commit current working copy'
task :commit => [:clobber, :test] do
    sh 'git log --stat=80 > ChangeLog'
    sh 'git commit -a'   
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

    statln = `git status | wc -l`.gsub(/\s/, '')
 
    unless statln == '2' or statln == '4'
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
    git_version = `git log HEAD^..HEAD | grep commit`.gsub('commit ', '').chomp

    open('lib/xmppd/version.rb', 'w') do |f|
        f.puts '#'
        f.puts '# synapse: a small XMPP server'
        f.puts '# version.rb: dynamically-generated version information'
        f.puts '#'
        f.puts '# Copyright (c) 2006 Eric Will <rakaur@malkier.net>'
        f.puts '#'
        f.puts
        f.puts "$version = '%s'" % ENV['VER']
        f.puts "$release_date = '%s'" % release_date
        f.puts "$git_version = '%s'" % git_version
    end

    puts '%s (%s)' % [ENV['VER'], git_version]
end
#
# Documentation generation.
#
# $ rake rdoc
#
Rake::RDocTask.new do |r|
    r.rdoc_dir = 'doc/rdoc'
    r.options << '--line-numbers' << '--inline-source'
    r.rdoc_files.include('lib/**/*', 'README')
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
    p.name = 'synapse'
    p.version = ENV['VER'] || $version
    p.need_tar = true
    p.need_zip = true
    p.package_files = PKG_FILES
end

spec = Gem::Specification.new do |s|
    s.name = 'synapse'
    s.version = ENV['VER'] || $version
    s.author = 'Eric Will'
    s.email = 'rakaur@malkier.net'
    s.homepage = 'http://synapse.malkier.net/'
    s.platform = Gem::Platform::RUBY
    s.summary = 'a small, lightweight XMPP server'
    s.files = PKG_FILES.to_a
    s.require_paths = ['lib']

    s.test_file = 'test/ts_xmppd.rb'
    s.has_rdoc = true
    s.extra_rdoc_files = ['README']

    s.rubyforge_project = 'xmppd'

    s.default_executable = 'xmppd'
    s.executables = ['xmppd']

    s.add_dependency('idn', '>= 0.0.1')
end

# Makes a .gem package.
Rake::GemPackageTask.new(spec) do
end
