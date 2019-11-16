require 'optparse'
require 'logger'
require 'socket'
require 'ostruct'
require_relative 'asf_packet'
require_relative 'media_server'

def parse_options
  options = {log_level: 'INFO'}
  OptionParser.new do |opt|
    opt.on('--console', 'コンソールにログを表示する') do |v|
      options[:console] = v
    end
    opt.on("--log-level [#{Logger::SEV_LABEL.join('|')}]", 'ログレベル') do |v|
      w = v.upcase
      if Logger::SEV_LABEL.include?(w)
        options[:log_level] = w
      else
        fail 'unknown log level'
      end
    end
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
log = options[:console] ? Logger.new(STDOUT) : Logger.new('mirror.log', 'daily')
log.level = Logger.const_get(options[:log_level])

MediaServer.new(log, options).run
