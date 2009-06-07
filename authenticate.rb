#!/usr/bin/ruby

config_file = './database.yml'
cfg = YAML.load_file(config_file)

host = cfg['host'] || '127.0.0.1'
db_con = "DBI:Mysql:#{cfg['database']}:#{host}"
@db = DBI.connect db_con, cfg['username'] , cfg['password']

buffer = String.new
while buffer = STDIN.sysread(2) && buffer.length == 2
  length = buffer.unpack('n')[0]
  operation, username, domain, password =
      STDIN.sysread(length).split(':')

  response = case operation
      when 'auth'
          auth username, password.chomp
      when 'isuser'
          isuser username
      else
          0
      end

  STDOUT.syswrite([2, response].pack('nn'))
end

def auth(username, password)
  row = @db.select_one("select password from users"\
    " where user_name = ? and activated_at IS NOT NULL",
    username)

  return (1 if row and row['password'] == password) || 0
end
