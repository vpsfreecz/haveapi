require 'spec_helper'

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

  def json_element(attribute)
    JSON.parse(last_response.body.match(%r{<script[^>]*#{attribute}[^>]*>(.*?)</script>}m)[1])
  end

  it 'renders only the selected resource actions and preserves stable example IDs' do
    get '/v1/?resource=widget'
    expect(last_response).to be_ok
    expect(last_response.body).to include('data-page="resource"', '<h1 class="resource" id="root-widget">widget</h1>', 'id="root-widget-show"',
                                          'id="example-widget-show-0-0"', 'data-detail="thorough"', 'PARENT_SAMPLE')
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

  it 'links nested resource breadcrumbs to the directory and each real parent' do
    get '/v1/?resource=widget.child'
    breadcrumb = last_response.body.match(%r{<nav aria-label="Breadcrumb" data-resource-breadcrumbs>(.*?)</nav>}m)[1]
    expect(breadcrumb).to include('href="/v1/?page=resources"', 'href="/v1/?resource=widget"',
                                  '<li aria-current="page">Child</li>')
    expect(last_response.body.index('data-action-nav')).to be < last_response.body.index('docs-preferences')
    expect(last_response.body).to include('data-theme-choice="auto"', 'data-theme-choice="light"', 'data-theme-choice="dark"')
    expect(last_response.body).not_to include('data-theme-select')
  end

  it 'keeps parameter values and validators readable in semantic compact tables' do
    get '/v1/?resource=widget'
    input = last_response.body.match(%r{<table class="docs-input-parameters">(.*?)</table>\s*</div>\s*<h\d>Output parameters}m)[1]
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
    expect(response.body).to include('src="/rack/js/documentation.js"',
                                     'data-highlighter-url="/rack/js/highlighter.js"',
                                     'href="/rack/css/documentation.css"',
                                     'href="/rack/v1/?page=resources"')
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
