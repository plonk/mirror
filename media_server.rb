require 'logger'
require 'monitor'
require_relative 'monitor_helper'
require_relative 'publishing_point'
require_relative 'client_connection'

# mirroring media server
class MediaServer
  def initialize(log = Logger.new(STDOUT), options = {})
    host = options[:host] || "0.0.0.0"
    port = options[:port] || 4567
    @socket = TCPServer.open(host, port)
    @listeners = []
    @publishing_points = {}
    @lock = Monitor.new
    @log = log
    @options = options
    log.info("server is on %s" % addr_format(@socket.addr))
  end

  def run
    threads = []
    loop do
      client = @socket.accept
      @log.info "connection accepted #{addr_format(client.peeraddr)}"

      threads = threads.select(&:alive?)
      threads << Thread.start(client) do |s|
        begin
          peeraddr = s.peeraddr # コネクションリセットされると取れなくなるので
          @log.info "thread #{Thread.current} started"
          handle_request(http_request(s))
          @log.info "done serving #{addr_format(peeraddr)}"
        rescue
          @log.info "thread #{Thread.current} exiting"
        end
      end
    end
  rescue Interrupt
    @log.info 'interrupt from terminal'
    threads.each { |t| t.kill }
    threads = []
    @log.info 'closing publishing points...'
    @publishing_points.each_pair do |path, point|
      point.close unless point.closed?
    end
  end

  private

  def addr_format(addr)
    address_family, port, hostname, numeric_address = addr
    "#{numeric_address}:#{port}"
  end

  include MonitorHelper

  # 既にパブリッシングポイントが存在すれば nil を返す
  def create_publishing_point(path)
    unless @publishing_points[path]
      @publishing_points[path] = PublishingPoint.new
      @log.info "publishing point #{path} created"
    end
    @log.debug "publishing points: #{@publishing_points.inspect}"
    @publishing_points[path]
  end
  make_safe :create_publishing_point

  def get_publishing_point(path)
    @publishing_points[path]
  end
  make_safe :get_publishing_point

  def remove_publishing_point(path)
    @log.info "removing point #{path}"
    @publishing_points.delete(path)
    @log.debug "publishing points: #{@publishing_points.inspect}"
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
    @log.debug "encoder request setup thus: #{setup_cmds.dump}"

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
    @log.debug 'handle_push_start' if $DEBUG
    s = request.socket

    publishing_point = create_publishing_point(request.path)
    if publishing_point
      begin
        @log.info "publisher starts streaming to #{publishing_point}"
        until publishing_point.closed?
          packet = AsfPacket.from_socket(s)
          @log.debug "RECEIVED: #{packet.inspect}"
          publishing_point << packet
        end
        @log.info "publisher finishes streaming to #{publishing_point}"
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
      @log.error "bad request %p" % request.headers['Content-Type']
      request.socket.close
    end
  end

  def download_granted?(addr)
    !@options[:local_only] || addr_format(addr).start_with?('127.')
  end

  def handle_subscriber_request(request)
    s = request.socket

    publishing_point = get_publishing_point(request.path)
    if !publishing_point
      s.write "HTTP/1.0 404 Not Found\r\n\r\n"
      s.close
    elsif download_granted?(request.socket.peeraddr)
      s.write "HTTP/1.0 200 OK\r\n"
      s.write "Server: Rex/9.0.2980\r\n"
      s.write "Cache-Control: no-cache\r\n"
      s.write "Pragma: no-cache\r\n"
      s.write "Pragma: features=\"broadcast,playlist\"\r\n"
      s.write "Content-Type: application/x-mms-framed\r\n"
      s.write "\r\n"

      publishing_point.add_subscriber ClientConnection.new(s)
    else
      @log.info "rejected download request from #{addr_format(request.socket.peeraddr)}"
      s.write "HTTP/1.0 403 Forbidden\r\n"
      s.write "\r\n"
      s.close
    end
  rescue => e
    @log.error "#{e.msg}"
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
