require "socket"
require 'ostruct'
require_relative 'asf_packet'
require_relative 'media_server'

MediaServer.new('0.0.0.0', 4567).run
