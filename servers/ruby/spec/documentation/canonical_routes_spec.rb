require 'spec_helper'

describe HaveAPI::Server, '#mount' do
  api do
    define_resource(:Ping) do
      version :all
      auth false
      define_action(:Show) do
        route 'ping'
        http_method :get
        output(:hash) { string :value }
        authorize { allow }
        def exec
          { value: 'pong' }
        end
      end
    end
  end

  def server_at(mount = '/')
    server = HaveAPI::Server.new(get_opt(:api_module))
    server.use_version([1, '7.0'])
    server.mount(mount)
    server
  end

  def request(server, method, path, **env)
    Rack::MockRequest.new(server.app).request(method, path, { 'HTTP_HOST' => 'example.test' }.merge(env))
  end

  it 'redirects only declared slashless GET/HEAD roots with raw query bytes and no loop' do
    server = server_at
    %w[GET HEAD].product(%w[1 7.0]).each do |method, version|
      query = 'page=resources&q=a+b%2f%2F&raw=%2520'
      response = request(server, method, "/v#{version}?#{query}")
      expect(response.status).to eq(308)
      expect(response['Location']).to eq("/v#{version}/?#{query}")
      expect(response['Cache-Control']).to eq('private, no-store')
      canonical = request(server, method, "/v#{version}/")
      expect(canonical.status).to eq(200)
      expect(canonical['Location']).to be_nil
    end
  end

  it 'includes Rack SCRIPT_NAME exactly once under the API mount' do
    server = server_at('/mounted/api/')
    response = request(server, 'GET', '/mounted/api/v7.0?resource=ping', 'SCRIPT_NAME' => '/rack')
    expect(response.status).to eq(308)
    expect(response['Location']).to eq('/rack/mounted/api/v7.0/?resource=ping')
  end

  it 'does not reinterpret unknown versions, action paths, OPTIONS or mutations as documentation redirects' do
    server = server_at
    [['GET', '/v2'], ['GET', '/v1/pings'], ['OPTIONS', '/v1'], ['POST', '/v1'], ['PUT', '/v1'], ['DELETE', '/v1']].each do |method, path|
      expect(request(server, method, path).status).not_to eq(308), "#{method} #{path}"
    end
    expect(request(server, 'GET', '/v1/pings/ping').status).to eq(200)
    expect(request(server, 'OPTIONS', '/v1/').status).to eq(200)
  end

  it 'rejects literal header controls but preserves their encoded query representation' do
    server = server_at
    ["a\rX: value", "a\n", "a\0", "a\x7f"].each do |query|
      response = request(server, 'GET', '/v1', 'QUERY_STRING' => query)
      expect(response.status).to eq(400)
      expect(response['Location']).to be_nil
      expect(response['Cache-Control']).to eq('private, no-store')
    end
    response = request(server, 'GET', '/v1?q=%0D%0A')
    expect(response.status).to eq(308)
    expect(response['Location']).to eq('/v1/?q=%0D%0A')
  end

  it 'keeps legacy login/logout as credential-free default-overview redirects' do
    server = server_at('/mounted/api/')
    allow(server.auth_chain).to receive(:authenticate).and_call_original
    %w[_login _logout].product(%w[GET HEAD]).each do |path, method|
      response = request(server, method, "/mounted/api/#{path}?back=https://foreign.example/", 'SCRIPT_NAME' => '/rack',
                                                                                               'HTTP_REFERER' => 'https://foreign.example/',
                                                                                               'HTTP_AUTHORIZATION' => 'Basic malformed')
      expect(response.status).to eq(303)
      expect(response['Location']).to eq('/rack/mounted/api/v7.0/')
      expect(response['Cache-Control']).to eq('private, no-store')
      expect(response['WWW-Authenticate']).to be_nil
      expect(response['Set-Cookie']).to be_nil
    end
    expect(server.auth_chain).not_to have_received(:authenticate)
  end
end
