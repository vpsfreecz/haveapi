# frozen_string_literal: true

require 'json'
require 'webrick'
require 'rackup'
require 'rackup/handler/webrick'

module RustClientFixtures
  # Keep the listener and shutdown signals in the fixture process. Port zero
  # lets the kernel reserve the port without a probe/close/rebind race.
  def self.serve(app, metadata: nil)
    server = nil
    %w[INT TERM].each { |signal| trap(signal) { server&.shutdown } }

    Rackup::Handler::WEBrick.run(
      app,
      Host: '127.0.0.1', Port: 0,
      AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
    ) do |instance|
      server = instance
      url = "http://127.0.0.1:#{server.listeners.first.addr[1]}"
      $stdout.puts "HAVEAPI_TEST_SERVER_READY #{url}"
      $stdout.puts "VPSADMIN_FIXTURE_READY #{JSON.generate(metadata.merge(base_url: url))}" if metadata
      $stdout.flush
    end
  end
end
