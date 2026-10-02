#!/usr/bin/env ruby
# Source-level contract probes, NOT a compiled-server/DB transaction test.
# Loads the actual patched runtime. Socket backpressure uses real socket pairs;
# the committed-session view below is a controlled model transaction seam.
require "socket"
require "json"
require "timeout"

root = File.expand_path(ARGV.fetch(0))
app_root = File.expand_path(ARGV.fetch(1))

module Tep
  class Request; end
  module WebSocket
    DEFAULT_MAX_FRAME = 16 * 1024 * 1024
    OPCODE_TEXT = 1
    OPCODE_CLOSE = 8
    CLOSE_POLICY_VIOLATION = 1008
  end
  App = Struct.new(:cable_conns, :cable_conns_lock, :cable_heartbeat)
  APP = App.new([], Mutex.new, 1) # Suppress unrelated heartbeat thread.
end

# Only the FFI adapter is replaced; Driver, Frame and Cable are loaded verbatim.
module Sock
  class << self
    attr_accessor :entered, :watch_fd
    def sphttp_write_bytes(fd, bytes, _size)
      entered << true if fd == watch_fd && entered
      Socket.for_fd(fd).tap { |socket| socket.autoclose = false }.write(bytes)
    rescue IOError, SystemCallError
      -1
    end

    def shutdown(fd, how)
      Socket.for_fd(fd).tap { |socket| socket.autoclose = false }.shutdown(how)
      0
    rescue IOError, SystemCallError
      -1
    end
  end
end

load "#{root}/runtime/spinel/tep/websocket/frame.rb"
load "#{root}/runtime/spinel/tep/websocket/driver.rb"
load "#{root}/runtime/spinel/cable.rb"

FAILURES = []
SOCKETS = []

def check(name, passed)
  puts "#{passed ? 'PASS' : 'FAIL'} #{name}"
  FAILURES << name unless passed
end

def driver(user_id)
  server, peer = Socket.pair(:UNIX, :STREAM, 0)
  SOCKETS.concat([ server, peer ])
  ws = Tep::WebSocket::Driver.new(server.fileno)
  ws.cable_user_id = user_id
  [ ws, server, peer ]
end

begin
  # Identity resolves before on_open registers. Pause at that boundary, revoke
  # the same user, then complete the already-authorized handshake.
  existing, = driver(101)
  pending, = driver(101)
  observer, = driver(102)
  Cable.register(existing)
  Cable.register(observer)
  Cable.disconnect_user(101, true)
  Cable.register(pending)
  check("registered affected socket retired", existing.retired?)
  check("unaffected socket remains usable", !observer.retired? && observer.text("control") > 0)
  check("handshake identified before revocation cannot register live afterward", pending.retired?)
  Tep::APP.cable_conns.clear

  # Exercise the real Campfire ban method with a deterministic transaction seam:
  # a separate reader still sees the committed session immediately after the
  # pre-commit disconnect. No real database isolation claim is made by this probe.
  module ActiveSupport
    module Concern; end
  end
  class User; end
  load "#{app_root}/app/models/user/bannable.rb"
  class BanProbe
    include User::Bannable
    attr_reader :reconnected, :committed
    def transaction
      @committed = false
      yield
      @committed = true
    end
    def create_bans_from_sessions; end
    def banned!; end
    def sessions = self
    def delete_all; end
    def remove_banned_content_later; end
    def close_remote_connections
      Cable.disconnect_user(201, false)
      unless @committed
        @reconnected, = driver(201)
        Cable.register(@reconnected)
      end
    end
  end
  ban = BanProbe.new
  ban.ban
  check("ban transaction seam completed", ban.committed)
  check("reconnect during ban commit window is retired by completed ban", ban.reconnected.retired?)
  Tep::APP.cable_conns.clear

  # Fill a real kernel send buffer, then enter the actual Driver's writer lock.
  # The queue proves the writer entered the FFI boundary before revoke starts.
  blocked, server, peer = driver(301)
  server.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, 4096)
  fill = "x" * 65536
  loop do
    break if server.write_nonblock(fill, exception: false) == :wait_writable
  end
  Sock.watch_fd = server.fileno
  Sock.entered = Queue.new
  writer = Thread.new { blocked.text(fill) }
  Timeout.timeout(2) { Sock.entered.pop }
  revoker = Thread.new { blocked.revoke(false) }
  completed = !revoker.join(0.5).nil?
  check("revocation completes within 500ms when peer never reads", completed)
  # Cleanup releases the genuine blocked write; never leave runaway threads.
  peer.close
  Timeout.timeout(2) { writer.join; revoker.join }
  check("backpressure fixture cleaned up after peer close", !writer.alive? && !revoker.alive?)
ensure
  SOCKETS.each { |socket| socket.close unless socket.closed? }
end
puts "source-level contract failures=#{FAILURES.length}; native/DB race certification is separate"
exit(FAILURES.empty? ? 0 : 1)
