require 'monitor'
require_relative 'monitor_helper'
require_relative 'publishing_point'
require_relative 'client_connection'

# mirroring media server
class MediaServer
  def initialize(ip, port)
    @socket = TCPServer.open(ip, port)
    @listeners = []
    @publishing_points = {}
    @lock = Monitor.new
    printf("server is on %s\n", @socket.addr.inspect) if $DEBUG
  end

  def run
    loop do
      Thread.start(@socket.accept) do |s|
        puts "connection accepted #{s}" if $DEBUG
        handle_request(http_request(s))
        puts "done serving #{s}"
      end
    end
  end

  private

  include MonitorHelper

  # 既にパブリッシングポイントが存在すれば nil を返す
  def create_publishing_point(path)
    unless @publishing_points[path]
      @publishing_points[path] = PublishingPoint.new
      puts "publishing point #{path} created" if $DEBUG
    end
    @publishing_points[path]
  end
  make_safe :create_publishing_point

  def get_publishing_point(path)
    @publishing_points[path]
  end
  make_safe :get_publishing_point

  def remove_publishing_point(path)
    puts "removing point #{path}" if $DEBUG
    @publishing_points.delete(path)
  end
  make_safe :remove_publishing_point

  def http_request(s)
    if (line = s.gets) =~ /\A([A-Z]+) (\S+) (\S+)\r\n\z/
      meth = $1
      path = $2
      version = $3
    else
      fail "invalid request line: #{line.inspect}"
    end

    # read headers
    headers = {}
    while (line = s.gets) != "\r\n"
      line =~ /\A([^:]+): (.+)\r\n\z/
      headers[$1] = $2
    end
    OpenStruct.new(meth: meth, path: path, version: version,
                   headers: headers, socket: s)
  end

  def handle_setup_request(request)
    s = request.socket

    # エンコーダーの設定要求を読む
    setup_cmds = s.read(request.headers['Content-Length'].to_i)
    puts 'setup'
    p setup_cmds

    # わかったふりをする
    headers = {
      'Server' => 'Cougar/9.01.01.3814',
      'Cache-Control' => 'no-cache',
      'Supported' => 'com.microsoft.wm.srvppair, com.microsoft.wm.sswitch, com.microsoft.wm.predstrm, com.microsoft.wm.fastcache, com.microsoft.wm.startupprofile',
      'Content-Length' => '0',
      'Connection' => 'Keep-Alive',
    }
    s.write "HTTP/1.1 204 No Content\r\n"
    headers.each { |key, val| s.write "#{key}: #{val}\r\n" }
    s.write "\r\n"

    # コネクションは閉じない
  end

  def handle_push_start(request)
    puts 'handle_push_start' if $DEBUG
    s = request.socket

    publishing_point = create_publishing_point(request.path)
    if publishing_point
      puts 'publishing point found'
      begin
        until publishing_point.closed?
          packet = AsfPacket.from_socket(s)
          puts "RECEIVED: #{packet.inspect}" if $DEBUG
          publishing_point << packet
        end
        puts 'point closed'
      rescue => e # ソケットエラー
        p e
      ensure
        publishing_point.close unless publishing_point.closed?
        remove_publishing_point(request.path)
      end
    else
      # なんかエラーを返す
      s.write "HTTP/1.0 404 Not Found\r\n\r\n"
    end
  end

  def handle_publisher_request(request)
    case request.headers['Content-Type']
    when 'application/x-wms-pushsetup'
      handle_setup_request(request)
      handle_request(http_request(request.socket)) # PUSH開始に移行する予定
    when 'application/x-wms-pushstart'
      handle_push_start(request)
    else
      # bad request
      puts 'bad request?'
      p request
      request.socket.close
    end
  end

  def handle_subscriber_request(request)
    s = request.socket

    publishing_point = get_publishing_point(request.path)
    if publishing_point
      s.write "HTTP/1.0 200 OK\r\n"
      s.write "Server: Rex/9.0.2980\r\n"
      s.write "Cache-Control: no-cache\r\n"
      s.write "Pragma: no-cache\r\n"
      s.write "Pragma: features=\"broadcast,playlist\"\r\n"
      s.write "Content-Type: application/x-mms-framed\r\n"
      s.write "\r\n"

      publishing_point.add_subscriber ClientConnection.new(s)
    else
      s.write "HTTP/1.0 404 Not Found\r\n\r\n"
    end
  rescue => e
    p e
  end

  def handle_request(request)
    case request.meth
    when "GET"
      handle_subscriber_request(request)
    when "POST"
      handle_publisher_request(request)
    else
      fail 'unknown method'
    end
  end
end
