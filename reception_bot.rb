#!/usr/bin/ruby

# This script will send a jabber message to the specified JID. The subject can be
# specified using the '-s' option, and the message will be taken from stdin.

require 'optparse'
require 'xmpp4r'
require 'xmpp4r/muc/helper/mucbrowser'
require 'xmpp4r/muc/helper/simplemucclient'
require 'xmpp4r/muc/iq/mucowner'
require 'xmpp4r/debuglog'
include Jabber

Jabber::logger = Logger.new('./log.txt')
Jabber::debug = true

class ReceptionBot
  def initialize
    @muc = nil
  end

  def run()
    connect()
    messageLoop()
  end

  def connect()
    @client = Client.new('reception-bot@ilya.local')    
    @client.connect
    @client.auth('12345')
    @browser = Jabber::MUC::MUCBrowser.new(@client)
  end

  def messageLoop()
    quit = false

    while not quit do
      print "> "
      $defout.flush
      line = gets
      quit = true if line.nil?
      if not quit
        command, args = line.split(' ', 2)
        args = args.to_s.chomp
        # main case
        case command
          when 'list', 'l'
            case args
              when 'rooms', 'r'
                listRooms()
              when 'users', 'u'
                puts @muc.roster.keys
            end
          when 'join', 'j'
            createRoom(args)
            listRooms
          when 'say', 's'
            say(args)
          when 'destroy', 'd'
            destroyRoom
            listRooms
          when 'room-for', 'rf'
            ensureRoomFor(args)
          when 'invite', 'i'
            invite(args)
          when 'exist', 'e'
            exist = roomExists?(args)
            puts exist ? 'yes' : 'no'
          when 'exit', 'q'
            quit = true
          else
            puts "Command \"#{command}\" unknown"
        end
      end
    end
    puts "Shut down"
  end

  def listRooms
    room_names = rooms().keys.collect {|each| each.to_s =~ /^([^@]+)@/; $1  }
    if @muc
      room_names = room_names.collect {|each| s = each == @muc.room ? "*" : " "; "#{s} #{each}" }
    end

    puts room_names
  end

  def say(text)
    @muc.say(text)
  end

  def destroyRoom
    begin
      @muc.destroy
      @muc = nil
    rescue Jabber::ServerError, RuntimeError
      p $!.to_s
    end
  end


  def createRoom(roomName)

    if @muc
      if @muc.room == roomName
        puts "already in room #{roomName}"
        return
      end
    end

    puts "joining #{roomName}"
    @muc = Jabber::MUC::SimpleMUCClient.new(@client)
    @muc.join(roomName + '@conference.ilya.local/bot')
    #@muc.configure(
    #        'muc#roomconfig_roomname' => roomName + ' Room',
    #        'muc#roomconfig_persistentroom' => 0,
    #        'muc#roomconfig_changesubject' => 0,
    #        'allow_private_messages' => 0)  
    
  end

  def invite(userName)
    @muc.invite({ userName => 'Hello'})
  end

  def ensureRoomFor(userName)
    userJid = Jabber::JID.new(userName)
    createRoom(userJid.node + '-room')
    invite(userName)
  end

  def rooms()
    @browser.muc_rooms('conference.ilya.local')
  end


  def roomExists?(room)
    roomJid  = Jabber::JID.new(room)
    rooms().include?(roomJid)
  end



  def print_time_line(time, line)
    if time.nil?
      puts line
    else
      puts "#{time.strftime('%I:%M')} #{line}"
    end
  end

end

bot = ReceptionBot.new
bot.run()