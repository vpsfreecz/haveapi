require 'spec_helper'

module DocumentationReferenceSpec
  module AuthenticationResources
    class Session < HaveAPI::Resource
      version :all
      auth false
      class Show < HaveAPI::Action
        route ''
        http_method :get
        input(:hash) { string :token }
        output(:hash) { string :token }
        authorize { allow }
        # rubocop:disable RSpec/NoExpectationExample
        example 'provider sample' do
          request(token: 'visible')
          response(token: 'visible')
        end
        # rubocop:enable RSpec/NoExpectationExample
      end
    end
  end

  class FirstProvider < HaveAPI::Authentication::Base
    auth_method :first
    def register_routes(_sinatra, _prefix)
      @server.routes[@version] ||= { authentication: {} }
      @server.routes[@version][:authentication][name] = { resources: {} }
    end

    def resource_module
      AuthenticationResources
    end
  end

  class SecondProvider < FirstProvider
    auth_method :second
    def resource_module
      AuthenticationResources
    end
  end
end

describe HaveAPI::DocumentationHelpers, '#render_version_documentation' do
  api do
    define_resource(:Parent) do
      version 1
      auth false
      define_action(:Index) do
        route ''
        http_method :get
        authorize { allow }
      end
      define_action(:Show) do
        route '{parent_id}'
        http_method :get
        output(:hash) { string :value }
        authorize { allow }
        # rubocop:disable RSpec/NoExpectationExample
        example '<Example>&' do
          path_params 1
          response(value: 'visible')
        end
        # rubocop:enable RSpec/NoExpectationExample
      end
      define_resource(:Child) do
        define_action(:Show) do
          route '{child_id}'
          http_method :get
          authorize { allow }
        end
        define_resource(:Grandchild) do
          define_action(:Show) do
            route '{grandchild_id}'
            http_method :get
            authorize { allow }
          end
        end
      end
    end
  end
  default_version 1

  def ids(body)
    body.scan(/\sid="([^"]+)"/).flatten
  end

  def assert_fragments(body)
    body.scan(/<a[^>]*\shref="#([^"]+)"/).flatten.each do |target|
      expect(ids(body).count(target)).to eq(1), target
    end
  end

  def reference(**options)
    Object.new.extend(described_class).documentation_reference_anchor(**options)
  end

  it 'encodes typed provider/resource/action/section/example tuples without delimiter collisions' do
    arguments = { resource_path: %w[a-b c], action_name: 'show', section: :input }
    target = reference(**arguments)
    expect(target).to eq(reference(**arguments))
    expect(JSON.parse([target.delete_prefix('reference-')].pack('H*'))).to eq([nil, %w[a-b c], 'show', 'input', nil])
    alternatives = [reference(**arguments, authentication: :first), reference(**arguments, authentication: :second),
                    reference(**arguments, resource_path: %w[a b-c]), reference(**arguments, section: :output),
                    reference(**arguments, example_index: 0), reference(**arguments, example_index: 1)]
    expect([target, *alternatives].uniq.length).to eq(7)
    expect(reference(resource_path: ['žluťoučký'], section: :examples)).to match(/\Areference-[0-9a-f]+\z/)
  end

  it 'provides native per-action sections including empty input/output and titled examples' do
    get '/v1/?resource=parent'
    expect(last_response).to be_ok
    body = last_response.body
    expect(body).to include('data-doc-nav-owner="root-parent-index"', 'data-doc-primary href="#root-parent-index"',
                            'data-doc-subnav="root-parent-index"', 'data-doc-subsection', 'No parameters.',
                            'aria-label="Link to Input parameters"', '&lt;Example&gt;&amp;')
    index_menu = body.match(%r{<ul data-doc-subnav="root-parent-index">(.*?)</ul>}m)[1]
    expect(index_menu).to include('Input parameters', 'Output parameters')
    expect(index_menu).not_to include('Examples')
    expect(body).to include('id="example-parent-show-0-examples"', 'id="example-parent-show-0-0"')
    expect(body).not_to include('data-doc-subnav="root-parent-index" hidden')
    assert_fragments(body)
    File.write(File.join(ENV['HAVEAPI_REFERENCE_FIXTURES'], 'resource.html'), body) if ENV['HAVEAPI_REFERENCE_FIXTURES']
  end

  it 'emits one panel per group declaration and page metadata from actual rendered groups' do
    ['/v1/', '/v1/?resource=parent', '/v1/?page=resources'].each do |path|
      get path
      body = last_response.body
      groups = body.scan(%r{<div class="docs-example" data-example data-example-details="([^"]*)" id="([^"]*)">(.*?)</div>}m)
      union = {}
      groups.each do |json, base, html|
        levels = JSON.parse(CGI.unescapeHTML(json))
        panels = html.scan(/data-client="([^"]+)"[^>]*data-detail="([^"]+)"/)
        expect(panels.sort).to eq(levels.flat_map { |client, details| details.map { |detail| [client, detail] } }.sort)
        expect(panels.uniq).to eq(panels)
        levels.each do |client, details|
          union[client] = (union.fetch(client, []) | details)
          if details == ['simple']
            expect(ids(body)).to include("#{base.delete_suffix('-examples')}-#{client}-thorough")
          end
        end
      end
      clients = JSON.parse(body.match(%r{data-documentation-clients>(.*?)</script>}m)[1])
      clients.each { |client| expect(client['details']).to eq(union.fetch(client['id'], ['simple'])) }
      expect(clients.find { |client| client['id'] == '0' }.fetch('details')).to eq(path == '/v1/?page=resources' ? ['simple'] : %w[simple thorough])
    end
  end

  it 'lists direct subresources with full dotted identities and reuses existing reference targets' do
    get '/v1/?resource=parent'
    sidebar = last_response.body.match(%r{<nav aria-label="Subresources">(.*?)</nav>}m)[1]
    expect(sidebar).to include('href="/v1/?resource=parent.child"', '>parent.child</a>')
    expect(sidebar).not_to include('grandchild')
    expect(last_response.body).to include('aria-label="Link to Subresources"', 'aria-label="Link to parent"')
    get '/v1/?resource=parent.child'
    expect(last_response.body).to include('>parent.child.grandchild</a>')
    get '/v1/'
    expect(last_response.body).to include('aria-label="Link to Initialization"', 'aria-label="Link to Client libraries"',
                                          'aria-label="Link to Using this reference"', 'aria-label="Documentation settings"')
    expect(last_response.body).not_to include('M4 6h16', 'Generated SDKs')
    assert_fragments(last_response.body)
  end

  it 'scopes duplicate authentication resource/action targets while keeping legacy aliases once' do
    server = HaveAPI::Server.new(get_opt(:api_module))
    server.use_version(1)
    server.auth_chain << DocumentationReferenceSpec::FirstProvider
    server.auth_chain << DocumentationReferenceSpec::SecondProvider
    server.mount('/')
    body = Rack::MockRequest.new(server.app).get('/v1/?page=authentication', 'HTTP_HOST' => 'example.test').body
    %i[first second].each do |provider|
      action = Object.new.extend(described_class).documentation_resource_target(resource_path: ['session'], action_name: :show, authentication: provider)
      expect(body).to include("data-doc-nav-owner=\"auth-#{provider}\"", "data-doc-subnav=\"auth-#{provider}\"", "href=\"##{action}\"")
      expect(ids(body).count(action)).to eq(1)
      %i[input output].each do |section|
        expect(body).to include("href=\"##{reference(resource_path: ['session'], action_name: :show, authentication: provider, section:)}\"")
      end
    end
    expect(ids(body).uniq.length).to eq(ids(body).length)
    %w[example-session-show-0-examples example-session-show-0-0 example-session-show-0-0-thorough].each do |legacy|
      expect(ids(body).count(legacy)).to eq(1)
    end
    expect(ids(body).count('root-session')).to eq(1)
    expect(ids(body).count('root-session-show')).to eq(1)
    expect(body.index('id="root-session-show"')).to be < body.index('id="auth-second"')
    assert_fragments(body)
    File.write(File.join(ENV['HAVEAPI_REFERENCE_FIXTURES'], 'authentication.html'), body) if ENV['HAVEAPI_REFERENCE_FIXTURES']
  end
end
