require 'spec_helper'
require 'rack/test'

module DocumentationOAuthSpec
  User = Struct.new(:login)

  class Config < HaveAPI::Authentication::OAuth2::Config
    class << self
      attr_accessor :users, :lookups
    end

    def base_url
      'https://issuer.example'
    end

    def find_user_by_access_token(_request, token)
      self.class.lookups << [@version, token]
      self.class.users[[@version, token]]
    end
  end

  Provider = HaveAPI::Authentication::OAuth2.with_config(Config)

  class BasicProvider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, username, password)
      User.new('basic-reader') if username == 'basic-reader' && password == 'basic-password'
    end
  end
end

describe HaveAPI::DocumentationOAuth do
  api do
    define_resource(:Public) do
      version 1
      auth false
      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        output(:hash) { string :value }
        authorize { allow }
      end
    end
    define_resource(:Secret) do
      version 1
      desc 'ROLE_FILTERED_RESOURCE'
      auth true
      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        output(:hash) { string :value }
        authorize { |user| user&.login == 'admin' ? allow : deny }
        def exec
          { value: 'private' }
        end
      end
      define_action(:Create, superclass: HaveAPI::Actions::Default::Create) do
        input(:hash) { string :value }
        output(:hash) { string :value }
        authorize { |user| user&.login == 'admin' ? allow : deny }
      end
    end
  end

  let(:oauth_options) do
    { client_id: 'docs-client', client_secret: 'CLIENT_SECRET_NOT_FOR_HTML', session_secret: 's' * 64,
      redirect_uri: 'https://docs.example/api/_documentation/oauth/callback', scope: ['all'], session_lifetime: 1800 }
  end
  let(:transport) { instance_double(described_class::Transport) }
  let(:token_reply) { JSON.generate(access_token: 'PRIVATE_ACCESS_TOKEN', token_type: 'Bearer', expires_in: 3600, refresh_token: 'IGNORED_REFRESH') }
  let(:post_authenticated) { [] }
  let(:api_server) { build_api_server }

  def build_api_server(versions: [1, 2], basic: false)
    server = HaveAPI::Server.new(self.class::ApiModule)
    server.use_version(versions)
    server.default_version = 1
    server.auth_chain << DocumentationOAuthSpec::BasicProvider if basic
    server.auth_chain << DocumentationOAuthSpec::Provider
    server.documentation_oauth(**oauth_options)
    server.connect_hook(:post_authenticated) do |ret, user|
      post_authenticated << user&.login
      ret
    end
    server.mount('/api/')
    server
  end

  before do
    DocumentationOAuthSpec::Config.users = { [1, 'PRIVATE_ACCESS_TOKEN'] => DocumentationOAuthSpec::User.new('admin') }
    DocumentationOAuthSpec::Config.lookups = []
    allow(described_class::Transport).to receive(:new).and_return(transport)
    allow(transport).to receive(:post).and_return(token_reply)
  end

  def app
    api_server.app
  end

  def secret_action_path(name)
    actions = api_server.routes.fetch(1).fetch(:resources).fetch(self.class::ApiModule::Secret).fetch(:actions)
    actions.find { |action, _| action.name.split('::').last.downcase == name.to_s }.last
  end

  def begin_login(query = {})
    get 'https://docs.example/api/_documentation/oauth/login', { version: '1', resource: 'secret', fragment: 'root-secret-index' }.merge(query)
    expect(last_response.status).to eq(302)
    URI.decode_www_form(URI(last_response.location).query).to_h
  end

  def sign_in
    authorization = begin_login
    get 'https://docs.example/api/_documentation/oauth/callback', code: 'one-use-code', state: authorization.fetch('state')
    expect(last_response.status).to eq(303)
    authorization
  end

  def cookie_headers
    Array(last_response.headers['set-cookie']).join("\n")
  end

  def capture_controls
    controls = []
    allow(api_server.documentation_oauth).to receive(:controls).and_wrap_original do |method, *args|
      result = method.call(*args)
      controls << result
      result
    end
    controls
  end

  def session_csrf
    get 'https://docs.example/api/v1/'
    last_response.body[/name="csrf" value="([^"]+)"/, 1].tap { |value| expect(value).not_to be_nil }
  end

  def expect_switch_refused(cookie, query, body, origin: 'https://docs.example', headers: {})
    name, value = cookie
    post "https://docs.example/api/_documentation/oauth/logout#{query}", body,
         { 'HTTP_ORIGIN' => origin, 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }.merge(headers)
    expect(last_response.status).to eq(403)
    expect(cookie_headers).to be_empty
    expect(rack_mock_session.cookie_jar.to_hash[name]).to eq(value)
    expect(transport).to have_received(:post).once
  end

  def expect_existing_session_after_failed_callback(cookie)
    name, value = cookie
    expect(last_response.status).to eq(400)
    expect(last_response.body).to include('Documentation sign-in failed', 'Try again')
    expect(cookie_headers).to include(name.sub(/_session\z/, '_pending'), 'max-age=0')
    expect(cookie_headers).not_to include("#{name}=")
    expect(rack_mock_session.cookie_jar.to_hash[name]).to eq(value)
    expect(rack_mock_session.cookie_jar.to_hash[name.sub(/_session\z/, '_pending')].to_s).to be_empty

    get 'https://docs.example/api/v1/?resource=secret'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('<span class="docs-identity">admin</span>')
    expect(DocumentationOAuthSpec::Config.lookups.last).to eq([1, 'PRIVATE_ACCESS_TOKEN'])
    expect(post_authenticated.last).to eq('admin')
  end

  it 'uses fixed issuer URLs, PKCE and encrypted scoped cookies, then restores a clean destination' do
    authorization = sign_in
    expect(authorization).to include('client_id' => 'docs-client', 'code_challenge_method' => 'S256', 'scope' => 'all')
    expect(transport).to have_received(:post) do |uri, parameters|
      expect(uri.to_s).to eq('https://issuer.example/api/_auth/oauth2/token')
      verifier = parameters.fetch('code_verifier')
      expect(authorization['code_challenge']).to eq(Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false))
      expect(parameters).to include('client_id' => 'docs-client', 'client_secret' => oauth_options[:client_secret])
    end
    expect(last_response.location).to eq('https://docs.example/api/v1/?resource=secret#root-secret-index')
    expect(cookie_headers).to include('secure', 'httponly', 'samesite=lax', 'path=/api/')
    expect(cookie_headers).not_to include('PRIVATE_ACCESS_TOKEN', oauth_options[:client_secret], 'IGNORED_REFRESH', 'domain=')
    get 'https://docs.example/api/v1/?resource=secret'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('ROLE_FILTERED_RESOURCE')
    expect(last_response.body).not_to include('PRIVATE_ACCESS_TOKEN', oauth_options[:client_secret], 'IGNORED_REFRESH')
    expect(last_response.headers).to include('Cache-Control' => 'private, no-store', 'Referrer-Policy' => 'no-referrer')
    expect(post_authenticated).to include('admin')
  end

  it 'consumes pending state and rejects replay without another token request' do
    authorization = sign_in
    cookie = rack_mock_session.cookie_jar.to_hash.find { |name, _| name.end_with?('_session') }
    get 'https://docs.example/api/_documentation/oauth/callback', code: 'one-use-code', state: authorization.fetch('state')
    expect_existing_session_after_failed_callback(cookie)
    expect(transport).to have_received(:post).once
  end

  context 'with an existing authenticated documentation session' do
    def sign_in_cookie
      sign_in
      rack_mock_session.cookie_jar.to_hash.find { |name, _| name.end_with?('_session') }
    end

    it 'preserves the session after an unsolicited callback without pending state' do
      cookie = sign_in_cookie
      get 'https://docs.example/api/_documentation/oauth/callback'
      expect_existing_session_after_failed_callback(cookie)
      expect(transport).to have_received(:post).once
    end

    { 'missing state' => { code: 'code' },
      'mismatched state' => { code: 'code', state: 'x' * 43 },
      'malformed state' => { code: 'code', 'state[]' => 'bad' } }.each do |failure, query|
      it "preserves the session after #{failure} and consumes pending state" do
        cookie = sign_in_cookie
        begin_login
        get 'https://docs.example/api/_documentation/oauth/callback', query
        expect_existing_session_after_failed_callback(cookie)
        expect(transport).to have_received(:post).once
      end
    end

    it 'preserves the session after cancellation with the expected state' do
      cookie = sign_in_cookie
      authorization = begin_login
      get 'https://docs.example/api/_documentation/oauth/callback', error: 'access_denied', state: authorization.fetch('state')
      expect_existing_session_after_failed_callback(cookie)
      expect(transport).to have_received(:post).once
    end

    it 'preserves the session after a callback with the expected state but no code' do
      cookie = sign_in_cookie
      authorization = begin_login
      get 'https://docs.example/api/_documentation/oauth/callback', state: authorization.fetch('state')
      expect_existing_session_after_failed_callback(cookie)
      expect(transport).to have_received(:post).once
    end

    it 'preserves the session after duplicate callback fields' do
      cookie = sign_in_cookie
      authorization = begin_login
      state = authorization.fetch('state')
      get "https://docs.example/api/_documentation/oauth/callback?code=code&state=#{state}&state=#{state}"
      expect_existing_session_after_failed_callback(cookie)
      expect(transport).to have_received(:post).once
    end

    it 'preserves the session when pending state expires' do
      cookie = sign_in_cookie
      authorization = begin_login
      allow(Time).to receive(:now).and_return(Time.now + 601)
      get 'https://docs.example/api/_documentation/oauth/callback', code: 'code', state: authorization.fetch('state')
      expect_existing_session_after_failed_callback(cookie)
      expect(transport).to have_received(:post).once
    end

    it 'preserves the session when token exchange fails' do
      cookie = sign_in_cookie
      authorization = begin_login
      allow(transport).to receive(:post).and_raise(described_class::Failure, 'PRIVATE_PROVIDER_ERROR')
      get 'https://docs.example/api/_documentation/oauth/callback', code: 'code', state: authorization.fetch('state')
      expect(last_response.body).not_to include('PRIVATE_PROVIDER_ERROR')
      expect_existing_session_after_failed_callback(cookie)
      expect(transport).to have_received(:post).twice
    end

    it 'preserves the session when token exchange returns an invalid reply' do
      cookie = sign_in_cookie
      authorization = begin_login
      allow(transport).to receive(:post).and_return('{invalid JSON')
      get 'https://docs.example/api/_documentation/oauth/callback', code: 'code', state: authorization.fetch('state')
      expect_existing_session_after_failed_callback(cookie)
      expect(transport).to have_received(:post).twice
    end
  end

  [nil, 'tampered'].each do |value|
    it "does not create a session after an unsolicited callback with #{value ? 'an invalid' : 'no'} session cookie" do
      if value
        sign_in
        name = rack_mock_session.cookie_jar.to_hash.keys.find { |key| key.end_with?('_session') }
        set_cookie "#{name}=#{value}; path=/api/", URI('https://docs.example/api/')
      end
      get 'https://docs.example/api/_documentation/oauth/callback', code: 'unsolicited', state: 'x' * 43
      expect(last_response.status).to eq(400)
      get 'https://docs.example/api/v1/?resource=secret'
      expect(last_response.status).to eq(200)
      expect(last_response.body).not_to include('class="docs-identity"', 'name="csrf"')
      expect(DocumentationOAuthSpec::Config.lookups).to be_empty
      expect(transport).to have_received(:post).exactly(value ? 1 : 0).times
    end
  end

  it 'returns to the validated resource directory and its fragment after sign-in' do
    get 'https://docs.example/api/_documentation/oauth/login', version: '1', page: 'resources', fragment: 'resources'
    expect(last_response.status).to eq(302)
    authorization = URI.decode_www_form(URI(last_response.location).query).to_h
    get 'https://docs.example/api/_documentation/oauth/callback', code: 'code', state: authorization.fetch('state')
    expect(last_response.status).to eq(303)
    expect(last_response.location).to eq('https://docs.example/api/v1/?page=resources#resources')
  end

  it 'rejects malformed directory selectors and arbitrary return locations' do
    ['?page[]=resources', '?page=resourcez', '?page=resources&resource=secret',
     '?page=resources&return=https://foreign.example/', '?page=resources&fragment=bad%2Fanchor'].each do |query|
      get "https://docs.example/api/_documentation/oauth/login#{query}"
      expect(last_response.status).to eq(400)
      expect(last_response.body).not_to include('foreign.example')
    end
    expect(transport).not_to have_received(:post)
  end

  it 'rejects a mismatched state, cancellation and duplicate callback inputs without exchanging a code' do
    [{ state: 'x' * 43, code: 'code' }, { error: 'access_denied' }, { 'state[]' => 'bad', code: 'code' }].each do |query|
      begin_login
      get 'https://docs.example/api/_documentation/oauth/callback', query
      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('Try again')
    end
    expect(transport).not_to have_received(:post)
  end

  it 'rejects an expired pending cookie' do
    authorization = begin_login
    allow(Time).to receive(:now).and_return(Time.now + 601)
    get 'https://docs.example/api/_documentation/oauth/callback', code: 'code', state: authorization.fetch('state')
    expect(last_response.status).to eq(400)
    expect(transport).not_to have_received(:post)
  end

  it 'bounds session expiry by its configured lifetime and clears expired sessions' do
    sign_in
    name, value = rack_mock_session.cookie_jar.to_hash.find { |key, _| key.end_with?('_session') }
    allow(Time).to receive(:now).and_return(Time.now + 1801)
    get 'https://docs.example/api/v1/', {}, 'HTTP_COOKIE' => "#{name}=#{Rack::Utils.escape(value)}"
    expect(last_response.status).to eq(200)
    expect(last_response.body).not_to include('ROLE_FILTERED_RESOURCE')
    expect(cookie_headers).to include('max-age=0')
  end

  it 'clears a tampered cookie and does not make its contents an API credential' do
    sign_in
    name = rack_mock_session.cookie_jar.to_hash.keys.find { |key| key.end_with?('_session') }
    set_cookie "#{name}=tampered; path=/api/", URI('https://docs.example/api/')
    get 'https://docs.example/api/v1/'
    expect(last_response.status).to eq(200)
    expect(DocumentationOAuthSpec::Config.lookups).to be_empty
    expect(cookie_headers).to include('max-age=0')
  end

  it 'revalidates the user role and token through the requested version' do
    sign_in
    get 'https://docs.example/api/v2/?resource=secret'
    expect(last_response.status).to eq(404)
    expect(DocumentationOAuthSpec::Config.lookups).to include([2, 'PRIVATE_ACCESS_TOKEN'])
    DocumentationOAuthSpec::Config.users[[1, 'PRIVATE_ACCESS_TOKEN']] = DocumentationOAuthSpec::User.new('member')
    sign_in
    get 'https://docs.example/api/v1/?resource=secret'
    expect(last_response.status).to eq(404)
  end

  it 'ignores the docs cookie for OPTIONS and API GET and POST actions' do
    sign_in
    options 'https://docs.example/api/v1/'
    expect(DocumentationOAuthSpec::Config.lookups).to be_empty
    get "https://docs.example#{secret_action_path(:index)}"
    expect(last_response.status).to eq(401)
    post "https://docs.example#{secret_action_path(:create)}", {}, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(401)
    expect(DocumentationOAuthSpec::Config.lookups).to be_empty
  end

  it 'preserves explicit Authorization and custom/query credential presence instead of adding cookie credentials' do
    sign_in
    [{ 'HTTP_AUTHORIZATION' => 'Bearer explicit' }, { 'HTTP_AUTHORIZATION' => 'broken' },
     { 'HTTP_X_HAVEAPI_OAUTH2_TOKEN' => 'explicit' }].each do |env|
      get 'https://docs.example/api/v1/', {}, env
      expect(last_response.status).to eq(200)
      expect(last_response.body).not_to include('ROLE_FILTERED_RESOURCE')
    end
    get 'https://docs.example/api/v1/?access_token=explicit'
    expect(DocumentationOAuthSpec::Config.lookups.map(&:last)).not_to include('PRIVATE_ACCESS_TOKEN')
  end

  it 'ignores the cookie on another origin and on plain HTTP' do
    sign_in
    name, value = rack_mock_session.cookie_jar.to_hash.find { |key, _| key.end_with?('_session') }
    cookie = "#{name}=#{Rack::Utils.escape(value)}"
    get 'http://docs.example/api/v1/', {}, 'HTTP_COOKIE' => cookie
    get 'https://foreign.example/api/v1/', {}, 'HTTP_COOKIE' => cookie
    expect(DocumentationOAuthSpec::Config.lookups).to be_empty
  end

  it 'preserves explicit credential conflicts and metadata-declared custom credentials' do
    sign_in
    get 'https://docs.example/api/v1/', {}, 'HTTP_AUTHORIZATION' => 'Bearer one', 'HTTP_X_HAVEAPI_OAUTH2_TOKEN' => 'two'
    expect(last_response.status).to eq(400)
    metadata = api_server.auth_chain.provider_descriptions(1)
    allow(api_server.auth_chain).to receive(:provider_descriptions).and_return(metadata.merge(
                                                                                 token: { http_header: 'X-Alternate-Token', query_parameter: :_alternate }
                                                                               ))
    get 'https://docs.example/api/v1/', {}, 'HTTP_X_ALTERNATE_TOKEN' => ''
    get 'https://docs.example/api/v1/?_alternate='
    expect(DocumentationOAuthSpec::Config.lookups).to be_empty
  end

  it 'binds encrypted sessions to the configured client even with the same server secret and mount' do
    sign_in
    name, value = rack_mock_session.cookie_jar.to_hash.find { |key, _| key.end_with?('_session') }
    other = HaveAPI::Server.new(self.class::ApiModule)
    other.use_version(1)
    other.auth_chain << DocumentationOAuthSpec::Provider
    other.documentation_oauth(**oauth_options, client_id: 'different-client')
    other.mount('/api/')
    response = Rack::MockRequest.new(other.app).get('https://docs.example/api/v1/',
                                                    'HTTP_HOST' => 'docs.example',
                                                    'HTTP_COOKIE' => "#{name}=#{Rack::Utils.escape(value)}")
    expect(response.status).to eq(200)
    expect(response.body).not_to include('ROLE_FILTERED_RESOURCE')
    expect(DocumentationOAuthSpec::Config.lookups).to be_empty
  end

  it 'requires same-origin and session CSRF before revocation' do
    sign_in
    post 'https://docs.example/api/_documentation/oauth/logout', csrf: 'wrong'
    expect(last_response.status).to eq(403)
    get 'https://docs.example/api/v1/'
    csrf = last_response.body[/name="csrf" value="([^"]+)"/, 1]
    expect(csrf).not_to be_nil
    post 'https://docs.example/api/_documentation/oauth/logout', { csrf: }, 'HTTP_ORIGIN' => 'https://foreign.example'
    expect(last_response.status).to eq(403)
    expect(transport).to have_received(:post).once
    get 'https://docs.example/api/v1/?resource=secret'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('ROLE_FILTERED_RESOURCE')
    post 'https://docs.example/api/_documentation/oauth/logout', { csrf: }, 'HTTP_ORIGIN' => 'https://docs.example'
    expect(last_response.status).to eq(303)
    expect(transport).to have_received(:post).with(have_attributes(path: '/api/_auth/oauth2/revoke'), hash_including('token' => 'PRIVATE_ACCESS_TOKEN'))
    expect(cookie_headers).to include('max-age=0')
    DocumentationOAuthSpec::Config.lookups.clear
    get 'https://docs.example/api/v1/?resource=secret'
    expect(last_response.status).to eq(200)
    expect(last_response.body).not_to include('class="docs-identity"', 'name="csrf"')
    expect(DocumentationOAuthSpec::Config.lookups).to be_empty
  end

  it 'clears local cookies and reports the revoke failure without leaking details' do
    sign_in
    get 'https://docs.example/api/v1/'
    csrf = last_response.body[/name="csrf" value="([^"]+)"/, 1]
    allow(transport).to receive(:post).and_raise(described_class::Failure, 'PRIVATE_PROVIDER_ERROR')
    post 'https://docs.example/api/_documentation/oauth/logout', { csrf: }, 'HTTP_ORIGIN' => 'https://docs.example'
    expect(last_response.status).to eq(502)
    expect(last_response.body).to include('Local sign-out succeeded', 'may remain until it expires')
    expect(last_response.body).not_to include('PRIVATE_PROVIDER_ERROR', 'PRIVATE_ACCESS_TOKEN')
    expect(cookie_headers).to include('max-age=0')
  end

  it 'disables user switching by default even for an authenticated documentation cookie' do
    sign_in
    controls = capture_controls
    csrf = session_csrf
    expect(controls.last).to include(signed_in: true)
    expect(controls.last).not_to have_key(:switch_user)
    cookie = rack_mock_session.cookie_jar.to_hash.find { |name, _| name.end_with?('_session') }
    expect_switch_refused(cookie, '', URI.encode_www_form(csrf:, switch_user: '1'))
  end

  it 'requires a strict Boolean switch-user capability' do
    [nil, 0, 1, 'true', 'false', [], {}].each do |value|
      expect { described_class.new(**oauth_options, switch_user: value) }.to raise_error(described_class::Invalid)
    end
    expect { described_class.new(**oauth_options, switch_user: false) }.not_to raise_error
  end

  context 'with user switching enabled' do
    let(:oauth_options) { super().merge(switch_user: true) }

    it 'offers switching only after validated documentation-cookie authentication' do
      controls = capture_controls
      get 'https://docs.example/api/v1/'
      expect(controls.last).to include(signed_in: false, csrf_token: nil)
      expect(controls.last).not_to have_key(:switch_user)
      sign_in
      get 'https://docs.example/api/v1/'
      expect(controls.last).to include(signed_in: true, switch_user: true)
      name = rack_mock_session.cookie_jar.to_hash.keys.find { |key| key.end_with?('_session') }
      set_cookie "#{name}=tampered; path=/api/", URI('https://docs.example/api/')
      get 'https://docs.example/api/v1/'
      expect(controls.last).to include(signed_in: false, csrf_token: nil)
      expect(controls.last).not_to have_key(:switch_user)
    end

    it 'revokes and clears the old session before starting fresh state and PKCE at the fixed login' do
      original = sign_in
      csrf = session_csrf
      post 'https://docs.example/api/_documentation/oauth/logout',
           { csrf:, switch_user: '1', version: '2', return: 'https://foreign.example/', scope: 'other' },
           'HTTP_ORIGIN' => 'https://docs.example'
      expect(last_response.status).to eq(303)
      expect(last_response.location).to eq('https://docs.example/api/_documentation/oauth/login?version=1')
      expect(cookie_headers).to include('_session=', '_pending=', 'max-age=0')
      expect(transport).to have_received(:post).with(have_attributes(path: '/api/_auth/oauth2/revoke'), hash_including('token' => 'PRIVATE_ACCESS_TOKEN'))
      get last_response.location
      expect(last_response.status).to eq(302)
      fresh = URI.decode_www_form(URI(last_response.location).query).to_h
      expect(fresh).to include('scope' => 'all', 'code_challenge_method' => 'S256')
      expect(fresh['state']).not_to eq(original['state'])
      expect(fresh['code_challenge']).not_to eq(original['code_challenge'])
      expect(fresh.keys & %w[prompt select_account]).to be_empty
      get 'https://docs.example/api/_documentation/oauth/callback', error: 'access_denied', state: fresh.fetch('state')
      expect(last_response.status).to eq(400)
      DocumentationOAuthSpec::Config.lookups.clear
      get 'https://docs.example/api/v1/'
      expect(last_response.body).not_to include('class="docs-identity"', 'name="csrf"')
      expect(DocumentationOAuthSpec::Config.lookups).to be_empty
      expect(transport).to have_received(:post).twice
    end

    [['', 'switch_user=0'], ['', 'switch_user='], ['', 'switch_user=true'],
     ['', 'switch_user=1&switch_user=1'], ['', 'switch_user[]=1'],
     ['', 'switch_user[mode]=1'], ['?switch_user=1', 'switch_user=1'],
     ['?switch_user=1&switch_user=1', '']].each do |query, fields|
      it "rejects malformed or repeated switch fields #{query} #{fields} before any sign-out effect" do
        sign_in
        csrf = session_csrf
        cookie = rack_mock_session.cookie_jar.to_hash.find { |name, _| name.end_with?('_session') }
        expect_switch_refused(cookie, query, "#{URI.encode_www_form(csrf:)}&#{fields}")
      end
    end

    it 'rejects multipart switching without extending the normal logout parser' do
      sign_in
      csrf = session_csrf
      cookie = rack_mock_session.cookie_jar.to_hash.find { |name, _| name.end_with?('_session') }
      boundary = 'documentation-switch-boundary'
      body = { csrf:, switch_user: '1' }.map do |name, value|
        "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
      end.join + "--#{boundary}--\r\n"
      expect_switch_refused(cookie, '', body, headers: { 'CONTENT_TYPE' => "multipart/form-data; boundary=#{boundary}" })
    end

    it 'requires the session CSRF and same origin before switching' do
      sign_in
      csrf = session_csrf
      cookie = rack_mock_session.cookie_jar.to_hash.find { |name, _| name.end_with?('_session') }
      expect_switch_refused(cookie, '', URI.encode_www_form(switch_user: '1'))
      expect_switch_refused(cookie, '', URI.encode_www_form(csrf: 'x' * 43, switch_user: '1'))
      expect_switch_refused(cookie, '', URI.encode_www_form(csrf:, switch_user: '1'), origin: 'https://foreign.example')
    end

    it 'keeps truthful local sign-out failure and does not redirect to fresh login when revocation fails' do
      sign_in
      csrf = session_csrf
      allow(transport).to receive(:post).and_raise(described_class::Failure, 'PRIVATE_REVOKE_ERROR')
      post 'https://docs.example/api/_documentation/oauth/logout', { csrf:, switch_user: '1' }, 'HTTP_ORIGIN' => 'https://docs.example'
      expect(last_response.status).to eq(502)
      expect(last_response.headers['location']).to be_nil
      expect(last_response.body).to include('Local sign-out succeeded', 'may remain until it expires')
      expect(last_response.body).not_to include('PRIVATE_REVOKE_ERROR')
      expect(cookie_headers).to include('_session=', '_pending=', 'max-age=0')
      DocumentationOAuthSpec::Config.lookups.clear
      get 'https://docs.example/api/v1/'
      expect(last_response.body).not_to include('class="docs-identity"', 'name="csrf"')
      expect(DocumentationOAuthSpec::Config.lookups).to be_empty
      expect(transport).to have_received(:post).twice
    end

    context 'with one version and an ordinary Basic provider alongside OAuth' do
      let(:api_server) { build_api_server(versions: [1], basic: true) }

      it 'presents the validated cookie identity and switch capability on the single-version index' do
        sign_in
        controls = capture_controls
        get 'https://docs.example/api/'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('data-account-menu', 'admin', 'name="switch_user" value="1"')
        expect(controls.last).to include(signed_in: true, switch_user: true)
        expect(DocumentationOAuthSpec::Config.lookups.last).to eq([1, 'PRIVATE_ACCESS_TOKEN'])
      end

      it 'uses Basic identity A and its filtering without offering OAuth cookie B controls or switching' do
        sign_in
        csrf = session_csrf
        cookie = rack_mock_session.cookie_jar.to_hash.find { |name, _| name.end_with?('_session') }
        controls = capture_controls
        authorization = "Basic #{Base64.strict_encode64('basic-reader:basic-password')}"
        DocumentationOAuthSpec::Config.lookups.clear
        get 'https://docs.example/api/', {}, 'HTTP_AUTHORIZATION' => authorization
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('data-account-menu', 'basic-reader')
        expect(last_response.body).not_to include('name="switch_user"', 'name="csrf"')
        expect(controls.last).to include(signed_in: false, csrf_token: nil)
        expect(controls.last).not_to have_key(:switch_user)
        get 'https://docs.example/api/v1/?resource=secret', {}, 'HTTP_AUTHORIZATION' => authorization
        expect(last_response.status).to eq(404)
        expect(DocumentationOAuthSpec::Config.lookups).to be_empty
        expect(post_authenticated.last).to eq('basic-reader')
        expect_switch_refused(cookie, '', URI.encode_www_form(csrf:, switch_user: '1'),
                              headers: { 'HTTP_AUTHORIZATION' => authorization })
        get 'https://docs.example/api/v1/?resource=secret'
        expect(last_response.status).to eq(200)
        expect(controls.last).to include(signed_in: true, switch_user: true)
      end

      it 'does not fall back to cookie B for malformed or conflicting explicit credentials' do
        sign_in
        controls = capture_controls
        [{ 'HTTP_AUTHORIZATION' => 'broken' },
         { 'HTTP_AUTHORIZATION' => 'Bearer one', 'HTTP_X_HAVEAPI_OAUTH2_TOKEN' => 'two' }].each do |headers|
          DocumentationOAuthSpec::Config.lookups.clear
          get 'https://docs.example/api/v1/', {}, headers
          expect(last_response.status).to eq(headers.length == 1 ? 200 : 400)
          expect(last_response.body).not_to include('name="switch_user"', 'name="csrf"')
          expect(DocumentationOAuthSpec::Config.lookups).to be_empty
          expect(controls.last).not_to include(switch_user: true)
        end
      end
    end
  end

  [{}, { access_token: 'token', token_type: 'Bearer', expires_in: 0 },
   { access_token: 'token', token_type: 'Bearer', expires_in: 'Infinity' },
   { access_token: 'x' * 4096, token_type: 'Bearer', expires_in: 60 }].each do |response|
    it "rejects invalid token reply shape #{response.keys.join('/')} without issuing an authenticated cookie" do
      allow(transport).to receive(:post).and_return(JSON.generate(response))
      authorization = begin_login
      get 'https://docs.example/api/_documentation/oauth/callback', code: 'code', state: authorization.fetch('state')
      expect(last_response.status).to eq(400)
      expect(cookie_headers).to include('max-age=0')
      expect(last_response.body).not_to include('CLIENT_SECRET_NOT_FOR_HTML')
    end
  end

  it 'rejects arbitrary return URLs, arrays and credential-like query keys' do
    ['?return=https://foreign.example/', '?version[]=1', '?version=1&version=2', '?access_token=secret', '?fragment=bad%2Fanchor'].each do |query|
      get "https://docs.example/api/_documentation/oauth/login#{query}"
      expect(last_response.status).to eq(400)
      expect(last_response.body).not_to include('foreign.example', 'secret')
    end
  end

  it 'rejects repeated configuration and configuration after mount without inspecting secrets' do
    app
    expect { api_server.documentation_oauth(**oauth_options) }.to raise_error(ArgumentError)
    expect(api_server.documentation_oauth.inspect).not_to include(oauth_options[:client_secret], oauth_options[:session_secret])
    unconfigured = HaveAPI::Server.new(self.class::ApiModule)
    unconfigured.use_version(1)
    unconfigured.mount('/api/')
    expect { unconfigured.documentation_oauth(**oauth_options) }.to raise_error(ArgumentError, /before mount/)
  end

  it 'rejects insecure config, missing secrets, unknown keys and invalid lifetimes/scopes' do
    [{ redirect_uri: 'http://docs.example/api/_documentation/oauth/callback' }, { session_secret: 'short' },
     { client_secret: [] }, { unknown: 'PRIVATE' }, { session_lifetime: 0 }, { session_lifetime: 86_401 },
     { scope: ['all wrong'] }].each do |changes|
      expect { described_class.new(**oauth_options, **changes) }.to raise_error(described_class::Invalid)
    end
  end

  it 'requires a matching mounted callback and OAuth provider metadata' do
    api = HaveAPI::Server.new(self.class::ApiModule)
    api.use_version([1, 2])
    api.default_version = 1
    api.documentation_oauth(**oauth_options)
    expect { api.mount('/different/') }.to raise_error(described_class::Invalid)
    second = HaveAPI::Server.new(self.class::ApiModule)
    second.use_version(1)
    second.documentation_oauth(**oauth_options)
    expect { second.mount('/api/') }.to raise_error(described_class::Invalid)
  end

  it 'reads only requested-version provider metadata without describing resources' do
    app
    allow(api_server).to receive(:describe_version).and_call_original
    expect(api_server.auth_chain.provider_descriptions(1)).to include(:oauth2)
    expect(api_server.auth_chain.provider_descriptions('absent')).to eq({})
    expect(api_server).not_to have_received(:describe_version)
  end
end
