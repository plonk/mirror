require_relative 'monitor_helper'

# パブリッシングポイント
class PublishingPoint
  include MonitorHelper

  def initialize
    @header = nil
    @subscribers = []
    @lock = Monitor.new
    @closed = false
  end

  def closed?
    @closed
  end

  def ready?
    @header != nil
  end
  make_safe :ready?

  def add_subscriber(subscriber)
    fail 'not ready' unless ready?
    subscriber << @header
    @subscribers << subscriber
  end
  make_safe :add_subscriber

  def <<(packet)
    if packet.type == :header
      puts 'header overwritten' if @header
      @header = packet
    else
      fail 'failed to receive initial header packet' unless @header

      @subscribers.each do |s|
        begin
          s << packet
        rescue StandardError => e
          puts "subscriber disconnected #{s}: #{e}"
          @subscribers.delete(s)
        end
      end
      if packet.type == :end_trans && packet.body == "\x00\x00\x00\x00"
        close
      end
    end
    self
  end
  make_safe(:<<)

  def close
    # close all subscriber connections
    @subscribers.each do |subscriber|
      begin
        subscriber.close
      rescue => e
        puts "an error occured while closing #{subscriber}: #{e.message}"
      end
    end
    @closed = true
  end
  make_safe :close
end
