require 'optparse'
require 'logger'
require 'socket'
require 'ostruct'
require_relative 'asf_packet'
require_relative 'media_server'

def parse_options
  options = {}
  OptionParser.new do |opt|
    opt.on('-d', 'デバッグ') do |v|
      $DEBUG = v
    end
    opt.on('--local-only', 'ローカルへしかストリーミングしない') do |v|
      options[:local_only] = v
    end
    opt.on('--host [HOSTNAME]', '待機するアドレス') do |v|
      options[:host] = v
    end
    opt.on('--port [NUM]', '待機するポート') do |v|
      options[:port] = v.to_i
    end
    opt.parse!(ARGV)
  end
  options
end

Process.setproctitle("mirror")

options = parse_options

if $DEBUG
  log = Logger.new(STDOUT)
  log.level = Logger::DEBUG
else
  log = Logger.new('mirror.log', 'daily')
  log.level = Logger::INFO
end

MediaServer.new(log, options).run
