require_relative 'asf_packet'

# クライアントとの接続
class ClientConnection
  attr_reader :socket, :seqno

  def initialize(socket)
    @socket = socket
    @seqno = 0
    @closing = false
  end

  def <<(packet)
    @closing = true if packet.type == :end_trans

    puts "sending packet #{packet.inspect} with seqno=#{@seqno}" if $DEBUG
    bytestr = packet.to_s(@seqno)
    @seqno += 1
    @socket.write(bytestr)
  end

  def close
    # send 4 END_TRANS's
    unless @closing
      3.times do
        self << AsfPacket.new(:end_trans, "\x01\x00\x00\x00")
      end
      self << AsfPacket.new(:end_trans, "\x00\x00\x00\x00")
    end
  ensure
    @socket.close
  end
end
