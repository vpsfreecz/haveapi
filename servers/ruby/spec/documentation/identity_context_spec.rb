require 'spec_helper'

module DocumentationIdentityContextSpec
  User = Struct.new(:login)

  class Provider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, username, password)
      User.new(username) if password == 'pass'
    end
  end
end

describe DocumentationIdentityContextSpec do
  api do
    define_resource(:Widget) do
      version :all
      auth false
      define_action(:Show) do
        route '{widget_id}'
        http_method :get
        output(:hash) { string :value }
        authorize { allow }
        def exec
          { value: 'unchanged' }
        end
      end
    end
  end
  default_version 1
  use_version 1
  auth_chain DocumentationIdentityContextSpec::Provider

  def configured_server(name: nil, versions: [1], mount: '/')
    server = HaveAPI::Server.new(get_opt(:api_module))
    server.use_version(versions)
    server.default_version = 1
    server.documentation_name = name
    server.auth_chain << DocumentationIdentityContextSpec::Provider
    server.mount(mount)
    server
  end

  def request(server, path, host: 'example.test', **env)
    Rack::MockRequest.new(server.app).get(path, { 'HTTP_HOST' => host }.merge(env))
  end

  it 'copies and freezes the trimmed display name without assigning any URL semantics' do
    server = HaveAPI::Server.new(get_opt(:api_module))
    original = '  <My API> & reference  '
    server.documentation_name = original
    original.replace('mutated')
    expect(server.documentation_name).to eq('<My API> & reference')
    expect(server.documentation_name).to be_frozen
    server.documentation_name = nil
    expect(server.documentation_name).to be_nil
  end

  it 'rejects empty, overlong, malformed and control-bearing names without replacing a valid name' do
    server = HaveAPI::Server.new(get_opt(:api_module))
    server.documentation_name = 'Valid'
    ['', '   ', 'x' * 257, "bad\nname", "\tbad", "bad\u007f", "\xff".b, :name, false].each do |value|
      expect { server.documentation_name = value }.to raise_error(ArgumentError)
      expect(server.documentation_name).to eq('Valid')
    end
    server.documentation_name = 'ž' * 128
    expect(server.documentation_name.bytesize).to eq(256)
    expect { server.documentation_name = 'ž' * 129 }.to raise_error(ArgumentError)
  end

  it 'escapes a long configured identity across mounted titles and brands while retaining API routes' do
    name = "<Example> & #{('long ' * 35).strip}"
    server = configured_server(name:, mount: '/api/')
    response = request(server, '/api/v1/?resource=widget')
    expect(response.status).to eq(200)
    expect(response.body).to include('<title>widget · API v1 · &lt;Example&gt; &amp;',
                                     '<a href="/api/">&lt;Example&gt; &amp;', '<small class="docs-api-version">API v1</small>')
    expect(response.body).not_to include('<Example>', 'api.vpsfree.cz')
    expect { server.documentation_name = nil }.to raise_error(ArgumentError, /before mount/)
    action = request(server, '/api/v1/widgets/1')
    expect(action.status).to eq(200)
    expect(JSON.parse(action.body).fetch('response').fetch('widget').fetch('value')).to eq('unchanged')
  end

  it 'uses the request host and nondefault port as fallback without inventing a canonical domain' do
    server = configured_server
    response = request(server, '/v1/', host: 'preview.example:8443')
    expect(response.status).to eq(200)
    expect(response.body).to include('<a href="/">preview.example:8443</a>', 'Overview · API v1 · preview.example:8443')
    response = request(server, '/v1/', host: 'preview.example:80')
    expect(response.body).to include('<a href="/">preview.example</a>')
  end

  it 'keeps explicit API credentials out of the sole-version documentation identity and describes once' do
    app
    server = instance_variable_get(:@api)
    allow(server.auth_chain).to receive(:authenticate).and_call_original
    allow(server).to receive(:describe).and_call_original
    events = []
    server.connect_hook(:post_authenticated) do |ret, user|
      events << user
      ret
    end
    login('<actual>&', 'pass')
    get '/'
    expect(last_response).to be_ok
    expect(last_response.body).to include('<h1>API versions</h1>', 'Showing all resources, actions and parameters.')
    expect(last_response.body).not_to include('docs-identity', 'docs-sign-in', 'API description', 'Available versions:')
    expect(server.auth_chain).not_to have_received(:authenticate)
    expect(server).to have_received(:describe).once.with(have_attributes(current_user: nil, auth_users_by_version: { 1 => nil }))
    expect(events).to eq([nil])
    expect(last_response.headers['Cache-Control']).to eq('private, no-store')
  end

  it 'keeps anonymous root search lazy without authentication or extraction' do
    app
    server = instance_variable_get(:@api)
    allow(server.auth_chain).to receive(:authenticate).and_call_original
    allow(server).to receive(:describe).and_call_original
    allow(HaveAPI::DocumentationSearch::Index).to receive(:new).and_call_original
    get '/'
    expect(last_response).to be_ok
    expect(last_response.body).to include('Showing all resources, actions and parameters.')
    expect(last_response.body).not_to include('docs-identity', 'class="authentication"')
    expect(server.auth_chain).not_to have_received(:authenticate)
    expect(server).to have_received(:describe).once
    expect(HaveAPI::DocumentationSearch::Index).not_to have_received(:new)
  end

  it 'resolves each multiversion documentation identity anonymously without borrowing API credentials' do
    server = configured_server(versions: [1, 2])
    allow(server.auth_chain).to receive(:authenticate).and_call_original
    allow(server).to receive(:describe).and_call_original
    events = []
    server.connect_hook(:post_authenticated) do |ret, user|
      events << user
      ret
    end
    response = request(server, '/', 'HTTP_AUTHORIZATION' => "Basic #{['member:pass'].pack('m0')}")
    expect(response.status).to eq(200)
    expect(response.body).to include('Version 1', 'Version 2')
    expect(response.body).not_to include('docs-identity', 'docs-visibility-note', 'class="docs-sign-in', 'class="docs-account-link')
    expect(server.auth_chain).not_to have_received(:authenticate)
    expect(server).to have_received(:describe).once.with(have_attributes(current_user: nil, auth_users_by_version: { 1 => nil, 2 => nil }))
    expect(events).to eq([nil, nil])
  end

  it 'keeps one settings disclosure with direct theme choices and no account actions when OAuth is absent' do
    server = configured_server(mount: '/api/')
    response = request(server, '/api/', 'SCRIPT_NAME' => '/rack')
    expect(response.status).to eq(200)
    expect(response.body).to include('href="/rack/api/"', 'href="/rack/api/v1/"', 'data-documentation-menu',
                                     'data-documentation-menu-content', 'aria-label="Documentation settings"')
    expect(response.body.scan('<details data-documentation-menu>').length).to eq(1)
    expect(response.body).not_to include('data-account-menu', 'data-theme-menu', 'docs-sign-in', 'docs-account-link', '_logout')
  end

  it 'keeps the documentation authentication boundary out of root OPTIONS and API actions' do
    app.helpers do
      def documentation_authenticated?(_version)
        raise 'Documentation-only authentication used for an API request'
      end
    end
    call_api(:options, '/')
    expect(last_response).to be_ok
    expect(api_response.response).to have_key(:versions)
    get '/v1/widgets/1'
    expect(last_response).to be_ok
    expect(api_response[:widget][:value]).to eq('unchanged')
  end

  it 'forwards renderer capabilities without pruning either panel detail level' do
    get '/v1/'
    clients = JSON.parse(last_response.body.match(%r{data-documentation-clients>(.*?)</script>}m)[1])
    expect(clients.find { |client| client['language'] == 'http' }.fetch('details')).to eq(['simple'])
    expect(clients.find { |client| client['id'] == 'javascript-async' }.fetch('details')).to eq(%w[simple thorough])
    expect(last_response.body).to include('data-detail-control', 'data-detail="simple"', 'data-detail="thorough"')
  end
end
