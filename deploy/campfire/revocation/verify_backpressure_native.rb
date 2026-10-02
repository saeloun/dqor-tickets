# Compile with the pinned Spinel compiler, -I <patched-roundhouse>/runtime/spinel.
# Actual Driver + Frame + sp_net; only the application shell and write-entry
# notification are synthetic. Run under an external 10-second timeout.
module Tep
  class Request; end
  module WebSocket
    DEFAULT_MAX_FRAME = 16777216
    OPCODE_TEXT = 1
    OPCODE_CLOSE = 8
    CLOSE_POLICY_VIOLATION = 1008
  end
  class Probe
    attr_accessor :entered, :completed
    def initialize
      @entered = Queue.new
      @completed = Queue.new
    end
  end
  APP = Probe.new
end
module Sock
  ffi_func :shutdown, [ :int, :int ], :int
  ffi_func :sp_net_listen_host, [ :str, :int, :int ], :int
  ffi_func :sp_net_local_port, [ :int ], :int
  ffi_func :sp_net_connect, [ :str, :int ], :int
  ffi_func :sp_net_accept, [ :int ], :int
  ffi_func :sp_net_set_nonblock, [ :int ], :int
  ffi_func :sp_net_write_partial, [ :int, :str, :int ], :int
  ffi_func :sp_net_write_bytes, [ :int, :str, :int ], :int
  ffi_func :sp_net_close, [ :int ], :int
  def self.sphttp_write_bytes(fd, bytes, size)
    Tep::APP.entered.push(true)
    Sock.sp_net_write_bytes(fd, bytes, size)
  end
end
require "tep/websocket/frame"
require "tep/websocket/driver"

listener = Sock.sp_net_listen_host("127.0.0.1", 0, 4)
raise "listen failed" if listener < 0
port = Sock.sp_net_local_port(listener)
peer = Sock.sp_net_connect("127.0.0.1", port)
fd = Sock.sp_net_accept(listener)
raise "connect failed" if peer < 0 || fd < 0
Sock.sp_net_set_nonblock(fd)
payload = "x" * 65536
filled = 0
while filled < 67108864
  accepted = Sock.sp_net_write_partial(fd, payload, payload.bytesize)
  break if accepted == 0
  raise "fill failed" if accepted < 0
  filled += accepted
end
raise "send buffer never filled" if filled >= 67108864
ws = Tep::WebSocket::Driver.new(fd)
writer = Thread.new { ws.text(payload) }
Tep::APP.entered.pop
revoker = Thread.new do
  ws.revoke(false)
  Tep::APP.completed.push(true)
end
sleep 0.5
completed = !Tep::APP.completed.empty?
puts "native revocation bounded before peer drains: #{completed}"
Sock.shutdown(peer, 2)
Sock.sp_net_close(peer)
writer.join
revoker.join
ws.retire
Sock.sp_net_close(fd)
Sock.sp_net_close(listener)
puts "native blocked writer and revoker cleaned up"
exit(completed ? 0 : 1)
