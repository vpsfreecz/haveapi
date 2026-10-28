require 'spec_helper'
require 'rack/mock'
require_relative '../../test_support/dynamic_documentation_api'

module DocumentationSearchRoutesSpec
  User = Struct.new(:login)

  class Provider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, username, password)
      User.new(username) if password == 'pass'
    end
  end
end

RSpec.describe HaveAPI::DocumentationSearch::Helpers do
  api do
    define_resource(:Widget) do
      version 1
      auth false
      define_action(:Renew) do
        http_method :post
        route 'renew'
        aliases ['extend']
        authorize do |user|
          input blacklist: [:private_ticket] unless user.login == 'admin'
          allow
        end
        input(:hash) do
          integer :lifetime, label: 'Lease duration'
          string :private_ticket, label: 'Secret ticket', default: 'DEFAULT_SECRET'
        end
        output(:hash) { string :valid_to, label: 'Expiry date' }
      end
      define_action(:Hidden) do
        http_method :post
        route 'hidden'
        authorize { |user| user.login == 'admin' ? allow : deny }
        output(:hash) { string :private_response }
      end

      define_resource(:Child) do
        define_action(:Show) do
          http_method :get
          route '{child_id}'
          authorize { allow }
          output(:hash) { string :name }
        end
      end
    end
  end
  default_version 1
  auth_chain DocumentationSearchRoutesSpec::Provider

  def results
    last_response.body.match(%r{<section data-search-results.*?</section>}m)[0]
  end

  it 'renders ordinary GET search forms on versions, resources and neutral guides without discovery for guides' do
    app
    server = instance_variable_get(:@api)
    allow(server).to receive(:describe_version).and_call_original
    get '/doc/protocol'
    expect(last_response.body).to include('data-documentation-search method="get" action="/v1/"',
                                          'name="page" value="resources"', 'name="q" data-search-query', 'Search API v1')
    expect(last_response.body).to include('placeholder="Resource..."')
    expect(server).not_to have_received(:describe_version)
    get '/v1/?page=resources'
    expect(last_response.body).to include('data-resource-nav', 'data-resource-link="widget"')
    expect(last_response.body).not_to include('data-search-results', 'data-resource-filter')
    ids = last_response.body.scan(/\bid="(docs-search-[^"]+)"/).flatten
    expect(ids).to contain_exactly('docs-search-sidebar-query', 'docs-search-directory-query')
  end

  it 'trims and escapes the query, title and results while describing exactly once' do
    app
    server = instance_variable_get(:@api)
    allow(server).to receive(:describe_version).and_call_original
    get '/v1/', page: 'resources', q: '  lease duration  '
    expect(last_response).to be_ok
    expect(last_response.headers['Cache-Control']).to eq('private, no-store')
    expect(last_response.body).to include('<title>Search API v1: lease duration', 'value="lease duration"')
    expect(results).to include('Parameter:', 'lifetime', 'Input', 'Integer')
    expect(server).to have_received(:describe_version).once
    get '/v1/', page: 'resources', q: '<script>evil</script>'
    expect(last_response.body).not_to include('<script>evil</script>')
    expect(results).to include('&lt;script&gt;evil&lt;/script&gt;', 'No matches')
  end

  it 'renders a nested resource full path and escaped ancestor context without a duplicate leaf label' do
    app
    server = instance_variable_get(:@api)
    allow(server).to receive(:describe_version).and_wrap_original do |original, *arguments|
      original.call(*arguments).tap { |help| help[:resources]['widget'][:resources]['child'][:label] = 'Child <node>' }
    end
    get '/v1/', page: 'resources', q: 'widget.child'
    expect(last_response).to be_ok
    expect(results).to include('Resource: <code>widget.child</code>', '<span>Widget · Child &lt;node&gt;</span>',
                               'href="/v1/?resource=widget.child"', '<span>widget.child · show</span>')
    expect(results).not_to include('Resource: <code>child</code>', '<span>child</span>', '<span>Child &lt;node&gt;</span>', '<node>')
  end

  it 'does not run query matching on unqueried pages or a query supplied to another page' do
    allow(HaveAPI::DocumentationSearch).to receive(:new).and_call_original
    ['/v1/', '/v1/?resource=widget', '/v1/?page=resources', '/v1/?page=resources&q=++', '/v1/?q=widget'].each do |path|
      get path
      expect(last_response).to be_ok
    end
    expect(HaveAPI::DocumentationSearch).not_to have_received(:new)
  end

  it 'rejects duplicate, bracketed, malformed UTF-8 and overlong search queries before describing' do
    app
    server = instance_variable_get(:@api)
    allow(server).to receive(:describe_version).and_call_original
    ['q=a&q=b', 'q[]=widget', 'q[x]=widget', 'q=%FF', 'q=%C0%AF', 'q=%ZZ', "q=#{'a' * 257}"].each do |query|
      response = Rack::MockRequest.new(app).get('/v1/', 'HTTP_HOST' => 'example.test', 'QUERY_STRING' => "page=resources&#{query}")
      expect(response.status).to eq(400), query
    end
    expect(server).not_to have_received(:describe_version)
    get '/v1/', page: 'resources', q: 'ž' * 256
    expect(last_response).to be_ok
  end

  it 'links parameter results to the exact row and keeps its owning action as a containing section' do
    get '/v1/', page: 'resources', q: 'lifetime'
    anchor = HaveAPI::DocumentationSearch.parameter_anchor(resource_path: ['widget'], action_name: 'renew',
                                                           direction: :input, parameter_name: 'lifetime')
    expect(results).to include("href=\"/v1/?resource=widget##{anchor}\"")
    get '/v1/?resource=widget'
    section = last_response.body.match(%r{<section data-doc-section id="root-widget-renew">(.*?)</section>}m)[1]
    expect(section).to include("<tr id=\"#{anchor}\"")
  end

  it 'links advertised provider parameters to their actual authentication-page rows' do
    request = Rack::MockRequest.new(DynamicDocumentationAPI.build.app)
    response = request.get('/mount/v2/?page=resources&q=token+request+user', 'HTTP_HOST' => 'example.test')
    expect(response.status).to eq(200)
    anchor = HaveAPI::DocumentationSearch.parameter_anchor(resource_path: ['token'], action_name: 'request',
                                                           direction: :input, parameter_name: 'user', authentication: :token)
    expect(response.body).to include("href=\"/mount/v2/?page=authentication##{anchor}\"", 'Authentication: token')
    page = request.get('/mount/v2/?page=authentication', 'HTTP_HOST' => 'example.test')
    expect(page.body).to include("<tr id=\"#{anchor}\"")
  end

  it 'keeps result links canonical under both API and Rack mounts and leaves OPTIONS query semantics unchanged' do
    server = HaveAPI::Server.new(get_opt(:api_module))
    server.use_version(1)
    server.mount('/api/')
    response = Rack::MockRequest.new(server.app).get('/api/v1/?page=resources&q=lifetime',
                                                     'HTTP_HOST' => 'example.test', 'SCRIPT_NAME' => '/rack')
    expect(response.status).to eq(200)
    expect(response.body).to include('action="/rack/api/v1/"', 'href="/rack/api/v1/?resource=widget#parameter-')
    call_api(:options, '/v1/?page=resources&q[]=bad&q=other')
    expect(last_response).to be_ok
    expect(api_response[:resources]).to have_key(:widget)
  end

  context 'with OAuth documentation sessions' do
    let(:documentation_server) do
      HaveAPI::Server.new(self.class.const_get(:ApiModule)).tap do |api|
        api.use_version(1)
        api.auth_chain << DocumentationSearchRoutesSpec::Provider
      end
    end
    let(:documentation_fixture) do
      require_relative '../../test_support/documentation_oauth_fixture'
      DocumentationOAuthFixture.configure(documentation_server, users: {
        1 => { 'member-token' => DocumentationSearchRoutesSpec::User.new('member'),
               'admin-token' => DocumentationSearchRoutesSpec::User.new('admin') }
      })
    end

    before do
      documentation_fixture
      documentation_server.mount('/')
      @api = documentation_server
    end

    it 'uses only cookie-user accessible parameters and actions while anonymous docs retain their full view' do
      get "#{documentation_fixture.origin}/v1/", page: 'resources', q: 'private_ticket'
      expect(results).to include('private_ticket')
      header 'Cookie', documentation_fixture.header_for(documentation_server, version: 1, token: 'member-token')
      login('admin', 'pass')
      get "#{documentation_fixture.origin}/v1/", page: 'resources', q: 'private_ticket'
      expect(results).not_to include('<code>private_ticket</code>', 'Secret ticket', 'DEFAULT_SECRET')
      get "#{documentation_fixture.origin}/v1/", page: 'resources', q: 'hidden'
      expect(results).not_to include('<code>hidden</code>', 'private_response')
      header 'Cookie', documentation_fixture.header_for(documentation_server, version: 1, token: 'admin-token')
      login('member', 'pass')
      get "#{documentation_fixture.origin}/v1/", page: 'resources', q: 'private_ticket'
      expect(results).to include('<code>private_ticket</code>')
      expect(documentation_fixture.lookups).to eq([[1, 'member-token'], [1, 'member-token'], [1, 'admin-token']])
    end
  end
end
