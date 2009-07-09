#!/usr/bin/ruby
# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require 'rubygems'
require 'xmpp4r/debuglog'
include Jabber

Jabber::logger = Logger.new(File.join(File.dirname(__FILE__), 'log.txt'))
Jabber::debug = true

class EjabberdAuthentication

  def initialize
    Jabber::logger << "starting logging"

    while (buffer = STDIN.sysread(2)) && buffer.length == 2
    Jabber::logger << "received message" 

        length = buffer.unpack('n')[0]
        operation, username, domain, password = STDIN.sysread(length).split(':')

        response = case operation
          when 'auth'
            Jabber::logger << "auth #{username} #{domain} #{password}\n"
            1
          when 'isuser'
            Jabber::logger << "isuser #{username}\n"
            1
          when 'setpass'
            Jabber::logger << "isuser #{username} #{domain} #{password}\n"
            1
          else
            0
        end

        STDOUT.syswrite([2, response].pack('nn'))
      end

      rescue Exception => exception
        puts 'Exception ' + exception.to_s
      end

end

EjabberdAuthentication.new