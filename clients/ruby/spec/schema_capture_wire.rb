# Run after review with the prepared Ruby-client HTTP dependencies.
require_relative '../lib/haveapi/schema'
require 'socket'
require 'timeout'
require 'tmpdir'
require 'stringio'
require 'base64'

def assert_capture(condition, message)
  raise message unless condition
end

def serve_capture(socket, requests)
  Timeout.timeout(2) do
    method, path = socket.gets.to_s.split(' ', 3)
    headers = {}
    size = 0
    while (line = socket.gets) && line != "\r\n"
      size += line.bytesize
      raise 'oversized fixture request' if size > 16_384

      name, value = line.split(':', 2)
      headers[name.downcase] = value.to_s.strip
    end
    requests << { method: method, path: path, headers: headers }
    if path == '/redirect/v7.0/'
      socket.write("HTTP/1.1 302 Found\r\nLocation: /redirect-target/v7.0/\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
      return
    end
    unless %w[/v7.0/ /mounted/v7.0/ /bad-header/v7.0/].include?(path) && method == 'OPTIONS'
      socket.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
      return
    end

    basic = "Basic #{Base64.strict_encode64('fixture-user:fixture-password')}"
    authorized = headers['authorization'] == basic || headers['x-fixture-token'] == 'fixture-token'
    resources = { 'public' => { 'actions' => {}, 'resources' => {} } }
    resources['authorized'] = { 'actions' => {}, 'resources' => {} } if authorized
    body = JSON.generate(
      'status' => true, 'version' => '2.0', 'response' => {
        'help' => path, 'meta' => { 'namespace' => '_meta' }, 'resources' => resources,
        'authentication' => {
          'token' => { 'http_header' => path.start_with?('/bad-header/') ? "X-Bad\r\nInjected" : 'X-Fixture-Token' }
        }
      }
    )
    socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
  end
ensure
  socket.close
end

server = TCPServer.new('127.0.0.1', 0)
requests = []
worker = Thread.new do
  loop { serve_capture(server.accept, requests) }
rescue IOError, Errno::EBADF
  raise unless server.closed?
end
worker.report_on_exception = false
previous = %w[HAVEAPI_CAPTURE_WIRE_PASSWORD HAVEAPI_CAPTURE_WIRE_TOKEN].to_h { |name| [name, ENV.fetch(name, nil)] }
ENV['HAVEAPI_CAPTURE_WIRE_PASSWORD'] = 'fixture-password'
ENV['HAVEAPI_CAPTURE_WIRE_TOKEN'] = 'fixture-token'

begin
  Timeout.timeout(20) do
    Dir.mktmpdir('haveapi-schema-wire-') do |dir|
      base = "http://127.0.0.1:#{server.addr[1]}"
      ['', '/mounted'].each do |mount|
        url = "#{base}#{mount}/v7.0/"
        {
          public: [],
          basic: ['--basic-user', 'fixture-user', '--basic-password-env', 'HAVEAPI_CAPTURE_WIRE_PASSWORD'],
          token: ['--token-env', 'HAVEAPI_CAPTURE_WIRE_TOKEN']
        }.each do |mode, auth|
          output = File.join(dir, 'schema.json')
          File.write(output, 'previous snapshot')
          out = StringIO.new
          err = StringIO.new
          first = requests.length
          status = HaveAPI::Schema::FetchCommand.run(
            [url, '--api-version', '7.0', '--profile', mode.to_s, '--output', output, *auth],
            command_name: 'schema-wire', out: out, err: err
          )
          assert_capture(status == 0, "capture failed for #{mount}/#{mode}")
          snapshot = HaveAPI::Schema::Snapshot.load(output)
          assert_capture(snapshot['source_url'] == url && snapshot['mount_path'] == "#{mount}/", 'version or mount changed')
          assert_capture(snapshot['description']['resources'].has_key?('authorized') == (mode != :public), 'wrong captured surface')
          assert_capture(File.binread(output) == HaveAPI::Schema::Snapshot.canonical(snapshot).b, 'noncanonical saved bytes')
          assert_capture(!File.read(output).include?('fixture-password') && !File.read(output).include?('fixture-token'), 'credential saved')
          observed = requests.drop(first)
          assert_capture(observed.length == (mode == :token ? 2 : 1), 'unexpected retry or auth action')
          assert_capture(observed.all? { |r| r[:method] == 'OPTIONS' && r[:path] == "#{mount}/v7.0/" }, 'endpoint changed')
          assert_capture(observed.all? { |r| r[:headers]['accept'].include?('json') }, 'JSON accept missing')
          if mode == :token
            assert_capture(!observed.first[:headers].has_key?('authorization') && !observed.first[:headers].has_key?('x-fixture-token'), 'discovery authenticated')
            assert_capture(observed.last[:headers]['x-fixture-token'] == 'fixture-token', 'advertised header unused')
          elsif mode == :basic
            assert_capture(observed.first[:headers]['authorization'] == "Basic #{Base64.strict_encode64('fixture-user:fixture-password')}", 'Basic credentials missing')
          end
          assert_capture(out.string.empty? && err.string.empty?, 'unexpected command diagnostics')
        end
      end

      %w[redirect bad-header].each do |failure|
        output = File.join(dir, 'schema.json')
        File.write(output, 'preserve on failure')
        err = StringIO.new
        first = requests.length
        status = HaveAPI::Schema::FetchCommand.run(
          ["#{base}/#{failure}/v7.0/", '--api-version', '7.0', '--profile', 'fixture',
           '--output', output, '--token-env', 'HAVEAPI_CAPTURE_WIRE_TOKEN'],
          command_name: 'schema-wire', out: StringIO.new, err: err
        )
        assert_capture(status == 1 && File.read(output) == 'preserve on failure', 'failed capture overwrote snapshot')
        assert_capture(requests.length - first == 1, 'redirect followed or token sent after invalid discovery')
        assert_capture(!err.string.include?('fixture-token') && !err.string.include?('Injected'), 'secret or header echoed')
      end
      assert_capture(Dir.children(dir) == ['schema.json'], 'temporary output leaked')
    end
    $stdout.puts 'Schema loopback: Public/Basic/existing-token root+mount capture, exact OPTIONS/header policy, redirects and atomic failure passed'
  end
ensure
  previous.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  server.close
  assert_capture(worker.join(2), 'fixture worker did not stop')
  worker.value
end
