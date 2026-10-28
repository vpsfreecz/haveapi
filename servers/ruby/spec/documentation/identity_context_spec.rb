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
    expect(response.body).to include('<title>Widget · API v1 · &lt;Example&gt; &amp;',
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

  it 'authenticates the sole-version index once and describes once using that same actual user' do
    app
    server = instance_variable_get(:@api)
    allow(server.auth_chain).to receive(:authenticate).and_call_original
    allow(server).to receive(:describe).and_call_original
    login('<actual>&', 'pass')
    get '/'
    expect(last_response).to be_ok
    expect(last_response.body).to include('<h1>API versions</h1>', 'data-account-menu',
                                          '<span class="docs-identity">&lt;actual&gt;&amp;</span>')
    expect(last_response.body).not_to include('API description', 'Available versions:', 'name="switch_user"')
    expect(server.auth_chain).to have_received(:authenticate).once
    expect(server).to have_received(:describe).once.with(have_attributes(current_user: have_attributes(login: '<actual>&'),
                                                                         auth_users_by_version: { 1 => have_attributes(login: '<actual>&') }))
    expect(last_response.headers['Cache-Control']).to eq('private, no-store')
  end

  it 'keeps anonymous sole-version root controls authoritative without a second authentication or search extraction' do
    app
    server = instance_variable_get(:@api)
    allow(server.auth_chain).to receive(:authenticate).and_call_original
    allow(server).to receive(:describe).and_call_original
    allow(HaveAPI::DocumentationSearch::Index).to receive(:new).and_call_original
    get '/'
    expect(last_response).to be_ok
    expect(last_response.body).to include('class="docs-sign-in login"', 'Showing all resources, actions and parameters.')
    expect(last_response.body).not_to include('docs-identity', 'data-account-menu')
    expect(server.auth_chain).to have_received(:authenticate).once
    expect(server).to have_received(:describe).once
    expect(HaveAPI::DocumentationSearch::Index).not_to have_received(:new)
  end

  it 'retains per-version authentication and hides identity on a multiversion index' do
    server = configured_server(versions: [1, 2])
    allow(server.auth_chain).to receive(:authenticate).and_call_original
    allow(server).to receive(:describe).and_call_original
    response = request(server, '/', 'HTTP_AUTHORIZATION' => "Basic #{['member:pass'].pack('m0')}")
    expect(response.status).to eq(200)
    expect(response.body).to include('Version 1', 'Version 2')
    expect(response.body).not_to include('data-account-menu', 'docs-identity', 'docs-visibility-note', 'class="docs-sign-in', 'class="docs-account-link')
    expect(server.auth_chain).to have_received(:authenticate).with(1, anything).once
    expect(server.auth_chain).to have_received(:authenticate).with(2, anything).once
    expect(server).to have_received(:describe).once
  end

  it 'keeps long actual logins and account destinations intact at a Rack-mounted index' do
    server = configured_server(mount: '/api/')
    login = '<reader>&' * 30
    credentials = { 'SCRIPT_NAME' => '/rack', 'HTTP_AUTHORIZATION' => "Basic #{["#{login}:pass"].pack('m0')}" }
    response = request(server, '/api/', **credentials)
    expect(response.status).to eq(200)
    expect(response.body).to include('href="/rack/api/"', 'href="/rack/api/v1/"',
                                     "<span class=\"docs-identity\">#{CGI.escapeHTML(login)}</span>",
                                     'class="logout" href="http://_log:out@example.test/rack/api/_logout"')
    expect(response.body.scan('class="docs-identity"').length).to eq(1)
    expect(response.body).not_to include(login, 'name="switch_user"')
  end

  it 'does not borrow a nondefault version identity to describe the default version' do
    server = configured_server(versions: [1, 2])
    user = DocumentationIdentityContextSpec::User.new('version-two-only')
    allow(server.auth_chain).to receive(:authenticate).with(1, anything).and_return(nil)
    allow(server.auth_chain).to receive(:authenticate).with(2, anything).and_return(user)
    allow(server).to receive(:describe).and_call_original
    response = request(server, '/')
    expect(response.status).to eq(200)
    expect(response.body).to include('Version 2')
    expect(response.body).not_to include('Version 1', 'version-two-only', 'data-account-menu')
    expect(server).to have_received(:describe).once.with(have_attributes(current_user: nil,
                                                                         auth_users_by_version: { 1 => nil, 2 => user }))
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
