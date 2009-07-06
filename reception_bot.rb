#!/usr/bin/ruby

# This script will send a jabber message to the specified JID. The subject can be
# specified using the '-s' option, and the message will be taken from stdin.

require 'rubygems'
require 'optparse'
require 'xmpp4r'
require 'xmpp4r/muc/helper/mucbrowser'
require 'xmpp4r/muc/helper/simplemucclient'
require 'xmpp4r/muc/iq/mucowner'
require 'xmpp4r/debuglog'
require 'xmpp4r/vcard/helper/vcard'
require 'xmpp4r/roster/helper/roster'
require 'xmpp4r/pubsub/helper/nodebrowser'
require 'xmpp4r/pubsub/helper/nodehelper'
require 'xmpp4r/pubsub/iq/pubsub'
require 'net/http'

include Jabber

Jabber::logger = Logger.new(File.join(File.dirname(__FILE__), 'reception-bot.log'))
Jabber::debug =  true

#NS_SHAREDGROUPS = 'http://jabber.org/protocol/shared-groups'
#class IqSharedGroups < XMPPElement
#  name_xmlns 'shared-groups', NS_SHAREDGROUPS
#  force_xmlns true
#end

WEB_SERVER =  'http://sergey.local:3000'
HOST = 'ilya.local'
PUBSUB_NODE = "pubsub.#{HOST}"
MUC_NODE = "conference.#{HOST}"
SHARED_GROUPS_NODE = "shared-groups.#{HOST}"

class ReceptionBot
  def initialize

    @mucs = []    
  end

  def connect()    
    @client = Client.new("reception-bot@#{HOST}")
    @client.add_message_callback do |m|
      if m.type != :error
        connect_user_with_operator(m.from)        
      end
    end

    @client.connect
    @client.auth('12345')
    @browser = Jabber::MUC::MUCBrowser.new(@client)
    @vcard = Jabber::Vcard::Helper.new(@client)
    @nodebrowser = Jabber::PubSub::NodeBrowser.new(@client)


    @roster = Jabber::Roster::Helper.new(@client)
    subscribe_to_roster
    @client.send(Jabber::Presence.new.set_show(:dnd).set_status('Waiting...beholding...'))


  end

  def prompt_after(&block)
    block.call()
    print "> "
    $defout.flush
  end

  def run_message_loop()
    quit = false

    prompt_after{}
    
    while not quit do      
      prompt_after {
        line = gets.strip
        quit = true if line.nil?
        if not quit
          command, args = line.split(' ', 2)
          args = args.to_s.chomp        
          case command
            when 'muc', 'm'
              command, args = args.split(' ', 2)
              case command
                when 'invite', 'i'
                  user, room = args.split(/\s+to\s+/)
                  muc_invite(user, room)
                when 'exists', 'e'
                  exist = muc_roomExists?(args)
                  puts exist ? 'yes' : 'no'
                when 'join', 'j'
                  muc_ensure_room(args)
                  muc_list_rooms
                when 'destroy', 'd'
                  muc_destroy_room(args)
                  muc_list_rooms
                when 'list', 'l'
                  command, args = args.split(' ', 2)
                  case command
                    when 'occupants', 'o'
                      muc = muc_for_room(args)
                      puts muc.roster.keys  if muc
                    when 'rooms', 'r'
                      muc_list_rooms
                  end
                when 'say', 's'
                  room, msg = args.split(' ', 2)
                  say(msg, room)
              end
            when 'roster', 'r'
              command, args = args.split(' ', 2)
              case command
                when 'list', 'l'
                  rost_print
                when 'add', 'a'
                  rost_subscribe_to(args)
                when 'remove', 'r'
                  rost_unsubscribe_from(args)
              end
            when 'register'
              @client.register('12345', {'first' => 'Ivan', 'last' => 'Bot'})
            when 'geturl'
              v = @vcard.get
              puts v['URL']
            when 'seturl'
              v = @vcard.get
              v['URL'] = args
              @vcard.set v
              #v = @vcard.get
              #puts v['URL']
            when 'pubsub', 'ps'
              command, args = args.split(' ', 2)
              case command
                when 'list', 'l'
                  pubsub_list_nodes args
              end
            when 'shared-groups', 'sg'
              command, args = args.split(' ', 2)
              case command
                when 'list', 'l'
                  sg_list
                when 'create', 'c'
                  sg_create_group(args)
                  sg_list
                when 'delete', 'd'
                  sg_delete_group(args)
                  sg_list
                when 'add', 'a'
                  group, user = args.split(/\s+to\s+/)
                  sg_add_user_to_group(user, group)
              end
            when 'server', 's'
              command, args = args.split(' ', 2)
              case command
                when 'operators', 'ops', 'o'
                  puts operators
              end
            when 'exit', 'q'
              quit = true
            else
              puts "Command \"#{command}\" unknown"
          end
        end
      }
    end        
    puts "\nShut down"
  end

  def host
    @client.jid.domain
  end

  def login_to_jid(name)
    name.gsub(/[@.]/, '_')
  end


  def operators
    #xml = Net::HTTP.get(URI.parse("#{WEB_SERVER}/operators.xml"))
    #doc = REXML::Document.new(xml)
    #ops = doc.get_elements('operators/operator/email')
    #ops.collect {|each| login_to_jid each.text}
    ops = []
    ops << "operator@ilya.local"
    ops
  end

  def print_node(name, level)
    begin
      items = @nodebrowser.items(PUBSUB_NODE, name)
      puts( ('  '*level) +  name)
      items.each {|info| print_node(name + '/' + info['name'], level+1)}
    rescue
      puts $!.to_s + name
    end
  end

  def pubsub_list_nodes(initial = nil)
    if(initial)
      print_node(initial, 0)
    else   
      names = @nodebrowser.nodes(PUBSUB_NODE)
      names.each {|name| print_node(name, 0) }
    end

  end

  def sg_list
    names = @nodebrowser.nodes(SHARED_GROUPS_NODE)
    puts names
  end

  def sg_create_group(name)
     Jabber::PubSub::NodeHelper.new(@client, SHARED_GROUPS_NODE, name, true)   
  end

  def sg_delete_group(name)
     helper = Jabber::PubSub::NodeHelper.new(@client, SHARED_GROUPS_NODE, name, false)
     helper.delete_node
  end

  def sg_add_user_to_group(user, group)
    puts "Not implemented yet"
  end

  def say(text, room_name)
    if not muc = muc_for_room(room_name)
      puts "not in room #{room_name}"
      return
    end
    muc.say(text)
  end

  def muc_list_rooms
    room_names = muc_rooms().keys.collect {|each| each.to_s =~ /^([^@]+)@/; $1  }
    room_names = room_names.collect {|each| s = muc_for_room(each) ? "*" : " "; "#{s} #{each}" }    
    puts room_names
  end

  def muc_for_room(room_name)
    @mucs.detect {|each| each.jid.node == room_name}
  end

  def muc_ensure_room(room_name, &block)
    if muc_for_room(room_name)
      puts "already in room #{room_name}"
      block.call() if block
      return
    end

    muc = Jabber::MUC::SimpleMUCClient.new(@client)
    muc.add_self_join_callback() do |pres|
      muc.configure(
            'muc#roomconfig_roomname' => room_name + ' Room',
            'muc#roomconfig_publicroom' => 1,
            'muc#roomconfig_persistentroom' => 1,
            'muc#roomconfig_changesubject' => 0,
            'allow_private_messages' => 0)
      block.call() if block
    end
    @mucs << muc

    puts "joining room '#{room_name}'"
    muc.join("#{room_name}@#{MUC_NODE}/bot")
  end

  def muc_destroy_room(room_name)
    if not muc = muc_for_room(room_name)
      puts "not in room #{room_name}"
      return
    end

    begin
      muc.destroy
      @mucs.delete muc
    rescue Jabber::ServerError, RuntimeError
      p $!.to_s
    end
  end

  def muc_invite(user_name, room_name)
    if not muc = muc_for_room(room_name)
      puts "not in room #{room_name}"
      return
    end
    
    muc.invite({ user_name => 'Hello'})
  end  

  def muc_rooms()
    @browser.muc_rooms(MUC_NODE)
  end


  def muc_roomExists?(room)
    room_jid  = Jabber::JID.new(room)
    muc_rooms().include?(room_jid)
  end

  def rost_subscribe_to(user_name)
    user_jid = Jabber::JID.new(user_name)
    @roster.add(user_jid)
  end

  def rost_unsubscribe_from(user_name)
    user_jid = Jabber::JID.new(user_name)
    @roster.remove(user_jid)
  end

  def rost_print
    @roster.groups.each do |group|
      if group.nil?
        puts "*** Ungrouped ***"
      else
        puts "*** #{group} ***"
      end

      @roster.find_by_group(group).each do |item|
        puts "- #{item.iname} (#{item.jid})"
      end

      print "\n"
    end

  end

  def subscribe_to_roster
    # Callback to handle updated roster items
    @roster.add_update_callback do |olditem, item|
        if !item
          puts "roster update: old item=#{olditem.jid}, subscription=#{olditem.subscription}"
        else
        
          if [:from, :none].include?(item.subscription) && item.ask != :subscribe
            puts("Subscribing to #{item.jid}")
            item.subscribe
          end

          # Print the item
          if olditem.nil?
            # We didn't knew before:          
            prompt_after { puts("received roster item #{item.jid}, subscription=#{item.subscription}") }
          else
            # Showing whats different:
            prompt_after { puts("received roster change #{olditem.iname} (#{olditem.jid}, #{olditem.subscription}) #{olditem.groups.join(', ')} -> #{item.iname} (#{item.jid}, #{item.subscription}) #{item.groups.join(', ')}") }
          end
        end
    end

    # Presence updates:
    @roster.add_presence_callback do |item, oldpres, pres|
      if pres.nil?
        # ...so create it:
        pres = Jabber::Presence.new
      end
      if oldpres.nil?
        # ...so create it:
        oldpres = Jabber::Presence.new
      end

      # Print name and jid:
      name = "#{pres.from}"
      if item.iname
        name = "#{item.iname} (#{pres.from})"
      end
      puts("changed presence of #{name}")

      # Print type changes:
      unless oldpres.type.nil? && pres.type.nil?
        puts("  type: #{oldpres.type.inspect} -> #{pres.type.inspect}")
      end
      # Print show changes:
      unless oldpres.show.nil? && pres.show.nil?
        puts("  show:     #{oldpres.show.to_s.inspect} -> #{pres.show.to_s.inspect}")
      end
      # Print status changes:
      unless oldpres.status.nil? && pres.status.nil?
        puts("  status:   #{oldpres.status.to_s.inspect} -> #{pres.status.to_s.inspect}")
      end
      # Print priority changes:
      unless oldpres.priority.nil? && pres.priority.nil?
        puts("  priority: #{oldpres.priority.inspect} -> #{pres.priority.inspect}")
      end
    end

    # Subscription requests and responses:
    subscription_callback = lambda { |item,pres|
      name = pres.from
      if item != nil && item.iname != nil
        name = "#{item.iname} (#{pres.from})"
      end
      case pres.type
        when :subscribe then puts("subscription request from #{name}")
        when :subscribed then puts("subscribed to #{name}")
        when :unsubscribe then puts("unsubscription request from #{name}")
        when :unsubscribed then puts("unsubscribed from #{name}")
        else raise "The @roster Helper is buggy!!! subscription callback with type=#{pres.type}"
      end
    }
    @roster.add_subscription_callback(0, nil, &subscription_callback)
    @roster.add_subscription_request_callback(0, nil, &subscription_callback)
  end

  def print_time_line(time, line)
    if time.nil?
      puts line
    else
      puts "#{time.strftime('%I:%M')} #{line}"
    end
  end

  def room_name_for_user(user)
    user.node.gsub(/[@.]/, '_') + '_room'
  end

  def connect_user_with_operator(user)
    puts "connecting #{user} with free operator"
    room_name = room_name_for_user(user)
    muc_ensure_room(room_name) { muc_invite(user, room_name); muc_invite(operators.first, room_name) }

  end


end

bot = ReceptionBot.new
bot.connect()
bot.run_message_loop()