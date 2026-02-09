# frozen_string_literal: true

require 'open3'
require 'net/http'
require 'timeout'
require 'uri'

class ClientTestServer
  READY_PREFIX = 'HAVEAPI_TEST_SERVER_READY'

  attr_reader :base_url

  def initialize
    @root = File.expand_path('../../../..', __dir__)
    @server_script = File.join(@root, 'servers', 'ruby', 'test_support', 'client_test_server.rb')
    @gemfile = File.join(@root, 'servers', 'ruby', 'Gemfile')
    @cwd = File.join(@root, 'clients', 'go')
  end

  def start
    return if @wait_thr

    env = { 'BUNDLE_GEMFILE' => @gemfile }
    cmd = ['bundle', 'exec', 'ruby', @server_script, '--port', '0']
    @stdin, @stdout, @wait_thr = Open3.popen2e(env, *cmd, chdir: @cwd)

    read_ready!
    wait_for_health!
  end

  def reset!
    ensure_started!

    uri = URI.join(@base_url, '/__reset')
    req = Net::HTTP::Post.new(uri)
    req['Content-Type'] = 'application/json'
    res = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }

    return if res.is_a?(Net::HTTPSuccess)

    raise "reset failed: #{res.code} #{res.body}"
  end

  def stop!
    return unless @wait_thr

    Process.kill('TERM', @wait_thr.pid)
    @wait_thr.value
  rescue Errno::ESRCH
    nil
  ensure
    @stdin&.close
    @stdout&.close
    @wait_thr = nil
  end

  private

  def ensure_started!
    start unless @wait_thr
  end

  def read_ready!
    Timeout.timeout(10) do
      while (line = @stdout.gets)
        next unless line.include?(READY_PREFIX)

        @base_url = line.split.last&.strip
        break
      end
    end

    raise 'server did not start' unless @base_url
  rescue Timeout::Error
    raise 'server did not start in time'
  end

  def wait_for_health!
    Timeout.timeout(5) do
      loop do
        begin
          uri = URI.join(@base_url, '/__health')
          res = Net::HTTP.get_response(uri)
          return if res.is_a?(Net::HTTPSuccess)
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, IOError
          # retry
        end

        sleep 0.05
      end
    end
  rescue Timeout::Error
    raise 'server did not become healthy in time'
  end
end
