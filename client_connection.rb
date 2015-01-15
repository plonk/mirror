require_relative 'asf_packet'

# クライアントとの接続
class ClientConnection
  attr_reader :socket, :seqno

  def initialize(socket)
    @socket = socket
    @seqno = 0
    @end_trans = false
  end

  def <<(packet)
    if @end_trans
      fail 'packet after END_TRANS'
    end

    @end_trans = true if packet.type == :end_trans && packet.body == "\x00\x00\x00\x00"

    puts "sending packet #{packet.inspect} with seqno=#{@seqno}" if $DEBUG
    bytestr = packet.to_s(@seqno)
    @seqno += 1
    @socket.write(bytestr)
  end

  def close
    unless @end_trans
      3.times do
        self << AsfPacket.new(:end_trans, "\x01\x00\x00\x00") # S_FALSE
      end
      self << AsfPacket.new(:end_trans, "\x00\x00\x00\x00") # S_OK
    end
  ensure
    @socket.close
  end
end
