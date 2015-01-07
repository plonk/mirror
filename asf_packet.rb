# Advanced System Format packet
# プリヘッダーはない
class AsfPacket
  TYPE_SYM = {
    "\x24\x43" => :clear,
    "\x24\x44" => :data,
    "\x24\x45" => :end_trans,
    "\x24\x48" => :header
  }
  SYM_TYPE = TYPE_SYM.invert

  attr_reader :type, :size, :body

  def self.from_socket(s)
    type = TYPE_SYM[s.read(2)]
    size, = s.read(2).unpack('v')
    body = s.read(size)
    AsfPacket.new(type, body)
  end

  def initialize(type, body)
    @type  = type
    @size  = body.bytesize
    @body  = body
  end

  def inspect
    if size < 10
      "#<#{self.class}:type=#{type},size=#{size},body=#{body.inspect}>"
    else
      "#<#{self.class}:type=#{type},size=#{size}}>"
    end
  end

  def to_s(seqno)
    [
      SYM_TYPE[@type],
      [@size + 8].pack('v'),
      [seqno].pack('V'),
      type == :header ? "\x00\x0c" : "\x00\x00",
      [@size + 8].pack('v'),
      @body
    ].join
  end
end
