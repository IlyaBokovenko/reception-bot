require(File.join(File.dirname(__FILE__), 'config', 'boot'))

require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'

require 'tasks/rails'
require 'ruby-debug'

desc "Auth Ejabberd User"
task :auth => :environment do

  buffer = String.new
  while (buffer = STDIN.sysread(2)) && buffer.length == 2
    length = buffer.unpack('n')[0]
    operation, username, domain, password = STDIN.sysread(length).split(':')

    response = case operation
        when 'auth'
            username == password.chomp ? 1 : 0
        when 'isuser'
            1
        else
            0
        end

    STDOUT.syswrite([2, response].pack('nn'))
  end
  puts 'exit'
end