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
require 'xmpp4r/dataforms'

include Jabber

logger = Logger.new(File.join(File.dirname(__FILE__), 'reception-bot.log'))
debug =  true

WEB_SERVER =  'http://sergey.local:3000'
WEB_LOGIN, WEB_PASS = "admin@example.com", "qweqwe"

JABBER_SERVER = 'ilya.local'
JABBER_LOGIN = "reception-bot@#{JABBER_SERVER}"
PUBSUB_NODE = "pubsub.#{JABBER_SERVER}"
MUC_NODE = "conference.#{JABBER_SERVER}"
SHARED_GROUPS_NODE = "shared-groups.#{JABBER_SERVER}"

class Presence
  def xjid
    x.items[0].jid
  end
end

class MUC::MUCClient
  def xjids
    roster.values.collect {|pres| pres.xjid}
  end  
  
  def bare_xjids
    xjids.collect {|each| each.bare}
  end
end

class ReceptionBot
  def initialize
    @mucs = []   
    @users_queue = [] 
  end
  
  def blabla
  end

  def connect()    
    @client = Client.new(JABBER_LOGIN)
    @client.add_message_callback do |m|
      if m.type != :error        
        connect_user_with_operator(m.from)      
      end
      true
    end

    @client.connect
    @client.auth('12345')
        
    @browser = MUC::MUCBrowser.new(@client)
    @vcard = Vcard::Helper.new(@client)
    @nodebrowser = PubSub::NodeBrowser.new(@client)

    @roster = Roster::Helper.new(@client)
    subscribe_to_roster
    @client.send(Presence.new.set_show(:dnd).set_status('Waiting...beholding...'))

    sg_restore_groups
    # join_all_rooms
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
                when 'get-config', 'gc'
                  sg_group_get_config(args) 
                when 'set-config', 'sc'                  
                  node, name, description, display_groups_str = args.split(/;\s*/,4)
                  display_groups = display_groups_str.split(/;\s*/)
                  sg_group_set_config(node, name, description, display_groups)
                when 'add', 'a'
                  group, user = args.split(' ', 2)
                  sg_add_user_to_group(user, group) 
                when 'remove', 'r'
                  group, user = args.split(' ', 2)
                  sg_remove_user_from_group(user, group) 
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
                when 'restore'
                  sg_restore_groups
              end
            when 'server', 's'
              command, args = args.split(' ', 2)
              case command
                when 'operators', 'ops', 'o'
                  puts operators.collect {|each|
                    online = @roster[each].online? ? "online" : ""
                    busy = operator_busy?(each) ? "busy" : ""
                    "#{each} #{online} #{busy}" 
                  }
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
    substs = [['_',''], ['@', 'at'], ['.', 'dot']]
    res = name
    substs.each {|key, val| res = res.gsub(key, '_' + val + '_')}
    res
  end


  def operators    
    # uri = URI.parse("#{WEB_SERVER}/operators.xml")
    # xml = nil
    # Net::HTTP.start(uri.host,uri.port) do |http|
    #   req = Net::HTTP::Get.new(uri.path)
    #   req.basic_auth WEB_LOGIN, WEB_PASS
    #   res = http.request(req)
    #   xml = res.body
    # end   
    # 
    # doc = REXML::Document.new(xml)
    # ops = doc.get_elements('operators/operator/email')
    # res = ops.collect {|each| login_to_jid each.text}        
    res = ["operator1", "operator2"]
    
    res.collect {|each| each + "@" + JABBER_SERVER}        
  end
  
  def customers
    res = ["user"]
    res.collect {|each| each + "@" + JABBER_SERVER}
  end
  
  def operator_busy?(op)
    op_jid = JID.new(op)
    @mucs.each { |muc|
      jids = muc.xjids
      roles = jids.collect {|jid| classify_jid(jid)}
      has_customer = roles.include? :customer      
      jids.each {|jid|        
          return has_customer if jid.bare == op_jid 
      }      
    }
    
    return false    
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
  
  def sg_restore_groups()
    group = "users"
    sg_delete_group group
    sg_create_group group
    sg_group_set_config(group, "all users", "All users should see each other", [group])
    users = ([JABBER_LOGIN] + operators)
    users.each {|each| sg_add_user_to_group(each, group)}
  end

  def sg_list
    names = @nodebrowser.nodes(SHARED_GROUPS_NODE)
    puts names
  end

  def sg_create_group(name)
     PubSub::NodeHelper.new(@client, SHARED_GROUPS_NODE, name, true)   
  end

  def sg_delete_group(name)
     helper = PubSub::NodeHelper.new(@client, SHARED_GROUPS_NODE, name, false)
     helper.delete_node
  end
  
  def sg_group_get_config(name)
    helper = PubSub::ServiceHelper.new(@client, SHARED_GROUPS_NODE)
    print helper.get_config_from(name)
  end
  
  def sg_group_set_config(group, name, description, display_groups)
    form = Dataforms::XData.new(:submit)
    form.add(Dataforms::XDataField.new('name')).value = name
    form.add(Dataforms::XDataField.new('description')).value = description
    form.add(Dataforms::XDataField.new('displayed_groups')).value = display_groups.join(';')
        
    helper = PubSub::ServiceHelper.new(@client, SHARED_GROUPS_NODE)    
    helper.set_config_for(group, form)
  end
  
  def sg_add_user_to_group(user, group)
    helper = PubSub::ServiceHelper.new(@client, SHARED_GROUPS_NODE)
    user_item = PubSub::Item.new
    user_item.text = user    
    helper.publish_item_to(group, user_item)
  end

  def sg_remove_user_from_group(user, group)
    helper = PubSub::ServiceHelper.new(@client, SHARED_GROUPS_NODE)
    user_item = PubSub::Item.new
    user_item.text = user    
    helper.delete_item_from(group, user_item)
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

    muc = MUC::SimpleMUCClient.new(@client)    
    muc.add_self_join_callback() do |pres|
      muc.configure(
            'muc#roomconfig_roomname' => room_name + ' Room',
            'muc#roomconfig_publicroom' => 1,
            'muc#roomconfig_persistentroom' => 1,
            'muc#roomconfig_changesubject' => 0,
            'allow_private_messages' => 0)
      block.call() if block
      true
    end
    muc.add_join_callback  {|presence| process_join(muc, presence); true}
    muc.add_leave_callback {|presence| process_leave(muc, presence); true}
    
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
    rescue ServerError, RuntimeError
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
    room_jid  = JID.new(room)
    muc_rooms().include?(room_jid)
  end

  def rost_subscribe_to(user_name)
    user_jid = JID.new(user_name)
    @roster.add(user_jid)
  end

  def rost_unsubscribe_from(user_name)
    user_jid = JID.new(user_name)
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
  
  def print_presence_change(item, oldpres, pres)
    if pres.nil?
       # ...so create it:
       pres = Presence.new
     end
     if oldpres.nil?
       # ...so create it:
       oldpres = Presence.new
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
        true
    end    

    # Presence updates:
    @roster.add_presence_callback do |item, oldpres, pres|
      prompt_after {
 
        print_presence_change(item, oldpres, pres)
        
        if pres and pres.type.nil? and classify_jid(pres.from) == :operator
          puts "operator #{pres.from} is online"
          on_operators_freed [pres.from]
        end        
      }
      true
    end

    # Subscription requests and responses:
    subscription_callback = lambda { |item,pres|
      prompt_after {
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
      true
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
  
  def find_free_operator_for_user(user)
    operators.detect {|each| @roster[each].online? and not operator_busy?(each)}
  end
  
  def connect_user_with_operator(user)    
    free_op = find_free_operator_for_user(user)
    if free_op
      puts "connecting #{user} with operator #{free_op}"
      room_name = room_name_for_user(user)
      muc_ensure_room(room_name) { 
        muc_invite(user, room_name)
        muc_invite(free_op, room_name) 
      }
    else      
      puts "no free operator found. Putting #{user} to waiting queue"              
      (@users_queue << user).uniq!
    end    
  end
  
  def classify_jid(jid)
    jid_str = jid.bare.to_s
    return :customer if customers.include? jid_str
    return :operator if operators.include? jid_str
    return :bot if jid_str == JABBER_LOGIN 
    return :unknown
  end
  
  def process_join(muc, pres)
    prompt_after {
      user_role = classify_jid(pres.xjid)
      puts "user #{pres.from.resource} (#{user_role}) has joined #{muc.room}"
    }
  end

  def process_leave(muc, pres)
    prompt_after {    
      user_role = classify_jid(pres.xjid)    
      puts "user #{pres.from.resource} (#{user_role}) has left #{muc.room}"        
      jids_left = {}
      muc.bare_xjids.each {|jid| jids_left[jid] = classify_jid(jid)}
      case user_role      
        when :customer
          if jids_left.values.include? :operator
            freed_ops = (jids_left.select {|jid, role| role == :operator}).collect {|jid_and_role| jid_and_role[0] }
            puts("customer left -> release room operator #{freed_ops}")
            on_operators_freed freed_ops
          end      
        when :operator
          if jids_left.values.include? :customer          
            user = jids_left.invert[:customer]
            puts("operator left -> find free operator for room customer #{user}")
            connect_user_with_operator(user)
          end        
      end
    }  
  end
  
  def on_operators_freed(freed_ops)
    user = @users_queue.shift
    if user
      puts "there is a user #{user} waiting for processing"
      connect_user_with_operator(user)
    end   
  end

end


bot = ReceptionBot.new
bot.connect()
bot.run_message_loop()