# frozen_string_literal: true

require 'optparse'
require 'socket'
require 'webrick'

begin
  require 'rackup'
  handler = Rackup::Handler::WEBrick
rescue LoadError
  require 'rack'
  handler = Rack::Handler::WEBrick
end

require_relative 'client_test_api'

options = {
  bind: '127.0.0.1',
  port: 0
}

OptionParser.new do |opts|
  opts.on('--bind HOST', 'Bind address (default 127.0.0.1)') do |v|
    options[:bind] = v
  end

  opts.on('--port PORT', Integer, 'Port to listen on (default 0)') do |v|
    options[:port] = v
  end
end.parse!(ARGV)

bind = options[:bind]
port = options[:port]

if port == 0
  tcp = TCPServer.new(bind, 0)
  port = tcp.addr[1]
  tcp.close
end

base_url = "http://#{bind}:#{port}"
api = HaveAPI::ClientTestAPI.build_server(base_url: base_url)

server = nil

trap('INT') { server&.shutdown }
trap('TERM') { server&.shutdown }

handler.run(
  api.app,
  Host: bind,
  Port: port,
  AccessLog: [],
  Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
) do |srv|
  server = srv
  puts "HAVEAPI_TEST_SERVER_READY #{base_url}"
  $stdout.flush
end
