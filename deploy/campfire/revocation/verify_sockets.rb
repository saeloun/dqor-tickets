#!/usr/bin/env ruby
# Synthetic local-only HTTP + already-open WebSocket regression.
# Uses the same client framing approach as campfire-cable-drive.rb (MIT).
require "net/http"
require "uri"
require "json"
require "socket"
require "websocket/driver"
require "open3"
require "cgi"

BASE = ARGV.fetch(0)
DB = ARGV.fetch(1)
URL = URI(BASE)
abort "local synthetic server only" unless URL.host == "127.0.0.1" && DB.start_with?("/tmp/dqor-campfire-revocation/")
PASSWORD = "synthetic-revocation-only"

def sql(query)
  out, status = Open3.capture2("/usr/bin/sqlite3", DB, query)
  raise "synthetic DB query failed" unless status.success?
  out.strip
end

def assert(value, message)
  raise message unless value
end

class Actor
  attr_reader :jar
  def initialize
    @jar = {}; @csrf = nil
  end
  def cookie = @jar.map { |k, v| "#{k}=#{v}" }.join("; ")
  def req(method, path, form = nil)
    klass = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post, "PATCH" => Net::HTTP::Patch, "DELETE" => Net::HTTP::Delete }.fetch(method)
    request = klass.new(URI(BASE + path))
    request["Cookie"] = cookie
    request["Accept"] = "text/vnd.turbo-stream.html, text/html"
    request["X-CSRF-Token"] = @csrf if @csrf
    request.set_form_data(form) if form
    response = Net::HTTP.start(URL.host, URL.port, read_timeout: 10) { |http| http.request(request) }
    Array(response.get_fields("set-cookie")).each { |c| k, v=c.split(";", 2).first.split("=", 2); @jar[k]=v }
    @csrf = CGI.unescapeHTML(response.body.to_s[/<meta name="csrf-token" content="([^"]+)"/, 1]) if response.body.to_s.include?('<meta name="csrf-token"')
    response
  end
end

class CableClient
  attr_reader :url, :messages, :closed
  def initialize(cookie)
    @url = "ws://#{URL.host}:#{URL.port}/cable"
    @socket = TCPSocket.new(URL.host, URL.port)
    @messages = []; @closed = false
    @driver = WebSocket::Driver.client(self, protocols: [ "actioncable-v1-json" ])
    @driver.set_header("Cookie", cookie)
    @driver.set_header("Origin", BASE)
    @driver.on(:message) { |e| @messages << JSON.parse(e.data) }
    @driver.on(:close) { @closed = true }
    @driver.on(:error) { @closed = true }
    @driver.start
  end
  def write(data) = @socket.write(data)
  def send_json(data) = @driver.text(JSON.generate(data))
  def pump(seconds = 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC)+seconds
    until Process.clock_gettime(Process::CLOCK_MONOTONIC)>=deadline || @closed
      next unless IO.select([ @socket ], nil, nil, 0.02)
      @driver.parse(@socket.read_nonblock(65536))
    end
  rescue EOFError, IOError, SystemCallError
    @closed = true
  end
  def subscribe(identifier)
    send_json(command: "subscribe", identifier:)
    pump(0.5)
  end
  def payload?(value) = @messages.any? { |m| m["message"].to_s.include?(value) }
  def close = @socket.close rescue nil
end

def identifier(actor, room)
  res=actor.req("GET", "/rooms/#{room}")
  assert(res.code=="200", "room read #{res.code}")
  tag=res.body[/<turbo-cable-stream-source[^>]*>/]
  assert(tag, "room has no stream source")
  JSON.generate(channel: tag[/channel="([^"]+)"/, 1], signed_stream_name: CGI.unescapeHTML(tag[/signed-stream-name="([^"]+)"/, 1]))
end

def post_message(actor, room, marker)
  res=actor.req("POST", "/rooms/#{room}/messages", { "message[body]"=>marker, "message[client_message_id]"=>marker })
  assert(res.code=="200", "message failed #{res.code}: #{res.body.to_s[0, 150]}")
end

owner=Actor.new
owner.req("GET", "/first_run")
res=owner.req("POST", "/first_run", { "user[name]"=>"Synthetic Owner", "user[email_address]"=>"owner@example.test", "user[password]"=>PASSWORD })
assert(res.code=="302", "fresh synthetic DB required: #{res.code}")
owner.req("GET", "/rooms/1")
join=sql("select join_code from accounts limit 1")
owner_id=sql("select id from users where email_address='owner@example.test'")
failures=[]
%w[logout membership role ban].each do |scenario|
  user=Actor.new
  user.req("GET", "/join/#{join}")
  res=user.req("POST", "/join/#{join}", { "user[name]"=>"Synthetic #{scenario}", "user[email_address]"=>"#{scenario}@example.test", "user[password]"=>PASSWORD })
  assert(res.code=="302", "signup #{scenario}: #{res.code}")
  id=sql("select id from users where email_address='#{scenario}@example.test'")
  room="1"
  if scenario=="membership"
    res=owner.req("POST", "/rooms/closeds", [ [ "room[name]", "Private synthetic" ], [ "user_ids[]", owner_id ], [ "user_ids[]", id ] ])
    assert(res.code=="302", "closed room create #{res.code}")
    room=res['location'][/rooms\/(\d+)/, 1]
  elsif scenario=="role"
    res=owner.req("PATCH", "/account/users/#{id}", { "user[role]"=>"administrator" })
    assert(res.code=="302", "promotion fixture failed #{res.code}")
  end
  stream=identifier(user, room)
  ws=CableClient.new(user.cookie); ws.pump(0.5); ws.subscribe(stream)
  assert(ws.messages.any? { |m|m['type']=='confirm_subscription' }, "#{scenario} subscription was not confirmed")
  second=CableClient.new(user.cookie); second.pump(0.5); second.subscribe(stream)
  observer=CableClient.new(owner.cookie); observer.pump(0.5); observer.subscribe(identifier(owner, room))
  [ second, observer ].each { |client| assert(client.messages.any? { |m|m['type']=='confirm_subscription' }, "control socket not subscribed") }
  forged=CableClient.new(user.cookie); forged.pump(0.5)
  forged.subscribe(JSON.generate(JSON.parse(stream).merge("channel"=>"Turbo::StreamsChannel")))
  assert(forged.messages.any? { |m|m['type']=='reject_subscription' }, "stock Turbo authorization guard regressed")
  forged.close
  marker="before-#{scenario}"
  post_message(owner, room, marker); [ ws, second, observer ].each { |client|client.pump(0.5) }
  assert([ ws, second, observer ].all? { |client|client.payload?(marker) }, "#{scenario} baseline broadcast missing")
  saved_cookie=user.cookie
  res=case scenario
  when "logout" then user.req("DELETE", "/session")
  when "membership" then owner.req("PATCH", "/rooms/closeds/#{room}", [ [ "room[name]", "Private synthetic" ], [ "user_ids[]", owner_id ] ])
  when "role" then owner.req("PATCH", "/account/users/#{id}", { "user[role]"=>"member" })
  when "ban" then owner.req("POST", "/users/#{id}/ban")
  end
  assert(%w[200 302 303].include?(res.code), "#{scenario} action failed #{res.code}: #{res.body.to_s[0, 150]}")
  [ ws, second ].each { |client|client.pump(0.5) }
  marker="after-#{scenario}"
  post_message(owner, room, marker); [ ws, second, observer ].each { |client|client.pump(0.5) }
  assert(observer.payload?(marker) && !observer.closed, "unaffected observer lost delivery")
  revoked=[ ws, second ].all? { |client|client.closed && !client.payload?(marker) }
  puts "#{scenario}: both_closed=#{ws.closed && second.closed}, post_revocation_delivery=#{ws.payload?(marker) || second.payload?(marker)}, unaffected_observer=true, stock_guard=true"
  failures << scenario unless revoked
  if scenario!="role"
    replay=CableClient.new(saved_cookie);replay.pump(0.5)
    replay.subscribe(stream) unless replay.closed
    rejected=replay.closed || replay.messages.any? { |m|m['type']=='reject_subscription' }
    puts "#{scenario}: replay_rejected=#{rejected}"
    failures << "#{scenario}-replay" unless rejected
    replay.close
  else
    res=user.req("PATCH", "/account/users/#{owner_id}", { "user[role]"=>"administrator" })
    puts "role: admin_http_status=#{res.code}"
    failures << "role-http" unless res.code == "403"
  end
  [ ws, second, observer ].each(&:close)
end
abort "FAIL: #{failures.join(', ')}" unless failures.empty?
puts "PASS: all existing sockets revoked; unauthorized replays rejected"
