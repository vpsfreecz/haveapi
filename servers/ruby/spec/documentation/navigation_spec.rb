require 'spec_helper'
require 'open3'

module DocumentationNavigationSpec
  User = Struct.new(:login)

  class Provider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, username, password)
      User.new(username) if password == 'pass'
    end
  end
end

module DocumentationNavigationSpec
  API = Module.new do
    def self.define_resource(name, &block)
      klass = Class.new(HaveAPI::Resource)
      const_set(name, klass)
      klass.class_exec(&block)
      klass
    end
    widget = define_resource(:Widget) do
      version 1
      auth false
      desc 'Parent resource description'

      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        input(:hash) do
          bool :enabled, default: false
          integer :count, default: 0
          string :empty, default: ''
          string :nullable, nullable: true, default: nil
          string :lifetime, validate: 'At least one hour, at most one week'
        end
        output(:hash) do
          integer :id
          string :label
        end
        authorize { allow }
      end

      define_action(:Show) do
        route '{widget_id}'
        http_method :get
        output(:hash) do
          integer :id
          string :label
          string :name
        end
        authorize { allow }

        # rubocop:disable RSpec/NoExpectationExample
        example 'parent sample' do
          path_params 1
          response(name: 'PARENT_SAMPLE')
        end
        # rubocop:enable RSpec/NoExpectationExample

        def exec
          { name: 'parent' }
        end
      end

      define_resource(:Child) do
        desc 'Nested resource description'
        define_action(:Show) do
          route '{child_id}'
          http_method :get
          output(:hash) { string :name }
          authorize { allow }

          # rubocop:disable RSpec/NoExpectationExample
          example 'child sample' do
            path_params 2
            response(name: 'CHILD_SAMPLE')
          end
          # rubocop:enable RSpec/NoExpectationExample
        end
      end
    end

    define_resource(:Reference) do
      version 1
      auth false
      define_action(:Show) do
        route '{reference_id}'
        http_method :get
        output(:hash) { resource widget }
        authorize { allow }
      end
    end

    define_resource(:Hidden) do
      version 1
      auth false
      desc 'HIDDEN_RESOURCE_DESCRIPTION'
      define_action(:Show) do
        route '{hidden_id}'
        http_method :get
        output(:hash) { string :secret }
        authorize { |user| user.login == 'admin' ? allow : deny }
      end
    end
  end
end

describe DocumentationNavigationSpec do
  api DocumentationNavigationSpec::API
  default_version 1
  auth_chain DocumentationNavigationSpec::Provider

  let(:documentation_server) { HaveAPI::Server.new(get_opt(:api_module)) }
  let(:docs_fixture) do
    require_relative '../../test_support/documentation_oauth_fixture'
    server = documentation_server
    server.use_version(1)
    server.auth_chain << DocumentationNavigationSpec::Provider
    users = %w[member admin].to_h { |name| [name, DocumentationNavigationSpec::User.new(name)] }
    fixture = DocumentationOAuthFixture.configure(server, users: { 1 => users })
    server.mount('/')
    @api = server
    fixture
  end

  def request_as(user, path)
    fixture = docs_fixture
    get "#{fixture.origin}#{path}", {}, 'HTTP_COOKIE' => fixture.header_for(documentation_server, version: 1, token: user)
  end

  def json_element(attribute)
    JSON.parse(last_response.body.match(%r{<script[^>]*#{attribute}[^>]*>(.*?)</script>}m)[1])
  end

  it 'renders an overview without resource actions and supplies visible legacy destinations' do
    request_as('member', '/v1/')
    expect(last_response).to be_ok
    expect(last_response.headers['Cache-Control']).to eq('private, no-store')
    expect(last_response.body).to include('data-page="overview"', 'init-0', '?resource=widget.child')
    expect(last_response.body).not_to include('PARENT_SAMPLE', 'CHILD_SAMPLE', 'HIDDEN_RESOURCE_DESCRIPTION')
    expect(json_element('data-legacy-anchors')).to include(
      'root-widget-show' => '/v1/?resource=widget',
      'root-widget-child-show' => '/v1/?resource=widget.child',
      'example-widget.child-show-' => '/v1/?resource=widget.child',
      'auth-basic' => '/v1/?page=authentication',
      'auth-basic-javascript-async' => '/v1/?page=authentication'
    )
    expect(json_element('data-legacy-anchors').keys.join).not_to include('hidden')
  end

  it 'renders only the selected resource actions and preserves stable example IDs' do
    get '/v1/?resource=widget'
    expect(last_response).to be_ok
    expect(last_response.body).to include('data-page="resource"', '<h1 class="resource" id="root-widget">widget<a class="docs-permalink"', 'id="root-widget-show"',
                                          'id="example-widget-show-0-0"', 'data-example-details', 'PARENT_SAMPLE')
    expect(last_response.body).not_to include('CHILD_SAMPLE', 'init-examples')
    expect(last_response.body).to include('data-resource-breadcrumbs', '<li aria-current="page">Widget</li>')
    expect(last_response.body).not_to include('data-resource-nav', 'class="docs-header"')
  end

  it 'renders nested resources on their own page with same-page action links' do
    get '/v1/?resource=widget.child'
    expect(last_response).to be_ok
    expect(last_response.body).to include('id="root-widget-child-show"', 'href="#root-widget-child-show"', 'CHILD_SAMPLE')
    expect(last_response.body).not_to include('PARENT_SAMPLE')
    sidebar = last_response.body.match(%r{<aside[^>]*>(.*?)</aside>}m)[1]
    expect(sidebar).to include('<p data-current-resource><a href="/v1/?resource=widget.child"><strong>widget.child</strong></a></p>')
    expect(sidebar).not_to include('<h2>Resource</h2>', '<code>widget.child</code>')
    expect(sidebar.index('data-current-resource')).to be < sidebar.index('aria-label="Actions on this resource"')
  end

  it 'keeps authentication content separate from the overview' do
    get '/v1/?page=authentication'
    expect(last_response).to be_ok
    expect(last_response.body).to include('data-page="authentication"', 'id="auth-basic"')
    expect(last_response.body).not_to include('PARENT_SAMPLE', 'init-examples')
  end

  it 'returns the same missing response for inaccessible and absent resources' do
    request_as('member', '/v1/?resource=hidden')
    expect(last_response.status).to eq(404)
    hidden_body = last_response.body
    request_as('member', '/v1/?resource=absent')
    expect(last_response.status).to eq(404)
    expect(last_response.body).to eq(hidden_body)
    expect(last_response.body).not_to include('HIDDEN_RESOURCE_DESCRIPTION')
  end

  it 'rejects malformed, duplicate, nested and ambiguous HTML selection' do
    %w[resource= resource=widget..child resource=../widget resource[]=widget resource[x]=widget
       resource=widget&resource=reference page=unknown page=authentication&resource=widget
       page=overview&page=authentication resource=%00].each do |query|
      get "/v1/?#{query}"
      expect(last_response.status).to eq(400), query
    end
  end

  it 'does not reinterpret selection on OPTIONS descriptions or action endpoints' do
    call_api(:options, '/v1/?resource=absent&page=unknown')
    expect(last_response).to be_ok
    expect(api_response[:resources]).to have_key(:widget)
    get '/v1/widgets/1?resource=absent&page=unknown'
    expect(last_response).to be_ok
    expect(api_response[:widget][:name]).to eq('parent')
  end

  it 'qualifies resource parameter links with the selected resource page' do
    get '/v1/?resource=reference'
    expect(last_response).to be_ok
    expect(last_response.body).to include('href="/v1/?resource=widget#root-widget-show"')
  end

  it 'preserves root version listing while supporting default-version selection' do
    get '/'
    expect(last_response.body).to include('<h1>API versions</h1>')
    get '/?resource=widget.child'
    expect(last_response).to be_ok
    expect(last_response.body).to include('CHILD_SAMPLE', 'href="/v1/?resource=widget"')
  end

  it 'keeps the complete authorized resource hierarchy on a separate directory page' do
    request_as('member', '/v1/?page=resources')
    expect(last_response).to be_ok
    expect(last_response.body).to include('data-page="resources"', 'data-resource-nav', 'data-documentation-search',
                                          'data-resource-link="widget.child"', 'data-search-query')
    expect(last_response.body).not_to include('PARENT_SAMPLE', 'CHILD_SAMPLE', 'data-resource-link="hidden"')
    get '/v1/'
    expect(last_response.body).to include('data-resource-directory-link', '?page=resources')
    expect(last_response.body).not_to include('data-resource-nav', 'data-resource-link="widget"')
    expect(json_element('data-legacy-anchors')['resources']).to eq('/v1/?page=resources')
  end

  it 'links nested resource breadcrumbs to the directory and each real parent' do
    get '/v1/?resource=widget.child'
    breadcrumb = last_response.body.match(%r{<nav class="docs-breadcrumb"[^>]*data-resource-breadcrumbs>(.*?)</nav>}m)[1]
    expect(breadcrumb).to include('href="/v1/?page=resources"', 'href="/v1/?resource=widget"',
                                  '<li aria-current="page">Child</li>')
    expect(last_response.body.index('data-action-nav')).to be < last_response.body.index('docs-preferences')
    expect(last_response.body).to include('data-theme-choice="auto"', 'data-theme-choice="light"', 'data-theme-choice="dark"')
    expect(last_response.body).not_to include('data-theme-select')
  end

  it 'keeps parameter values and validators readable in semantic compact tables' do
    get '/v1/?resource=widget'
    input = last_response.body.match(%r{<table class="docs-input-parameters">(.*?)</table>\s*</div>\s*<h\d[^>]*>Output parameters}m)[1]
    output = last_response.body.match(%r{<table class="docs-output-parameters">(.*?)</table>}m)[1]
    expect(input.scan('<th>').length).to eq(4)
    expect(output.scan('<th>').length).to eq(3)
    expect(input).to include('docs-param-details', 'Default:</strong> <code>false</code>',
                             'Default:</strong> <code>0</code>', 'Default:</strong> <code>&quot;&quot;</code>',
                             'Default:</strong> <code>null</code>', '<table class="docs-validator-table">',
                             '<caption>Validation rules</caption>', '<th scope="row">Custom</th>', 'At least one hour, at most one week')
    expect(last_response.body).to include('class="docs-table-scroll" tabindex="0" role="region" aria-label="Input parameters"')
    expect(input).not_to include('<dl>')
  end

  it 'keeps client presentation metadata safe in JSON script text' do
    payload = '</script><script>window.injected = true</script>'
    client = HaveAPI::ClientExample.clients.first
    allow(client).to receive(:language_label).and_return(payload)
    get '/v1/'
    expect(last_response.body).not_to include(payload)
    expect(json_element('data-documentation-clients').first.fetch('language_label')).to eq(payload)
  end

  it 'rejects malformed raw percent escapes before describing the version' do
    response = Rack::MockRequest.new(app).get('/v1/',
                                              'HTTP_HOST' => 'example.test', 'QUERY_STRING' => 'resource=%ZZ')
    expect(response.status).to eq(400)
  end

  it 'resolves documentation assets and the highlighter under a Rack mount' do
    response = Rack::MockRequest.new(app).get('/v1/?resource=widget',
                                              'HTTP_HOST' => 'example.test', 'SCRIPT_NAME' => '/rack')
    expect(response.status).to eq(200)
    digests = HaveAPI::DocumentationHelpers::ASSET_DIGESTS
    expect(response.body).to include("src=\"/rack/js/documentation.js?v=#{digests.fetch('js/documentation.js')}\"",
                                     'data-highlighter-url="/rack/js/highlighter.js"',
                                     "href=\"/rack/css/documentation.css?v=#{digests.fetch('css/documentation.css')}\"",
                                     'href="/rack/v1/?page=resources"')
  end

  it 'versions the entry assets by installed content without reading files during requests' do
    public_root = File.expand_path('../../lib/haveapi/public', __dir__)
    digests = HaveAPI::DocumentationHelpers::ASSET_DIGESTS
    expect(digests).to eq(%w[js/documentation.js css/documentation.css].to_h do |asset|
      [asset, Digest::SHA256.file(File.join(public_root, asset)).hexdigest]
    end)
    expect(digests).to be_frozen
    expect(digests.values).to all(be_frozen)
    allow(Digest::SHA256).to receive(:file).and_call_original
    %w[en cs].each do |locale|
      get "/v1/?doc_lang=#{locale}"
      digests.each do |asset, digest|
        expect(last_response.body).to include("/#{asset}?v=#{digest}\"")
      end
    end
    expect(Digest::SHA256).not_to have_received(:file)
    digests.each do |asset, digest|
      get "/#{asset}?v=#{digest}"
      expect(last_response).to be_ok
      expect(last_response.body).to eq(File.binread(File.join(public_root, asset)))
    end
  end

  it 'retains content versions across loads and changes only the modified asset version' do
    helper_path = File.expand_path('../../lib/haveapi/documentation_helpers.rb', __dir__)
    script = <<~RUBY
      require 'tmpdir'
      require 'fileutils'
      Dir.mktmpdir('haveapi-assets') do |root|
        path = File.join(root, 'documentation_helpers.rb')
        FileUtils.cp(ARGV.fetch(0), path)
        %w[js/documentation.js css/documentation.css].each do |asset|
          target = File.join(root, 'public', asset)
          FileUtils.mkdir_p(File.dirname(target))
          File.write(target, asset)
        end
        load path
        first = HaveAPI::DocumentationHelpers::ASSET_DIGESTS
        HaveAPI::DocumentationHelpers.send(:remove_const, :ASSET_DIGESTS)
        load path
        unchanged = HaveAPI::DocumentationHelpers::ASSET_DIGESTS
        File.write(File.join(root, 'public/js/documentation.js'), 'changed JavaScript')
        HaveAPI::DocumentationHelpers.send(:remove_const, :ASSET_DIGESTS)
        load path
        puts JSON.generate([first, unchanged, HaveAPI::DocumentationHelpers::ASSET_DIGESTS])
      end
    RUBY
    output, status = Open3.capture2e(RbConfig.ruby, '-e', script, helper_path)
    expect(status).to be_success, output
    first, unchanged, changed = JSON.parse(output)
    expect(unchanged).to eq(first)
    expect(changed.fetch('css/documentation.css')).to eq(first.fetch('css/documentation.css'))
    expect(changed.fetch('js/documentation.js')).to eq(Digest::SHA256.hexdigest('changed JavaScript'))
    expect(changed.fetch('js/documentation.js')).not_to eq(first.fetch('js/documentation.js'))
  end

  it 'uses mounted canonical navigation and keeps shared documentation on its layout' do
    server = HaveAPI::Server.new(get_opt(:api_module))
    server.use_version(1)
    server.mount('/mounted/api/')
    response = Rack::MockRequest.new(server.app).get('/mounted/api/v1/?resource=reference', 'HTTP_HOST' => 'example.test')
    expect(response.status).to eq(200)
    expect(response.body).to include('href="/mounted/api/v1/?resource=widget#root-widget-show"', '/js/documentation.js')
    expect(response.body).not_to include('href="/mounted/api/doc/protocol"')
    expect(response.body).not_to include('/js/nojs-tabs.js', '/js/main.js')
    get '/doc/protocol'
    expect(last_response).to be_ok
    expect(last_response.body).to include('/js/documentation.js', 'data-page="guide"')
    expect(last_response.body).not_to include('/js/main.js')
  end
end
