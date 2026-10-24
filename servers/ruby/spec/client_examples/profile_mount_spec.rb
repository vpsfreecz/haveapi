require 'spec_helper'
require 'base64'

module ProfileMountSpec
  User = Struct.new(:login)

  module AuthenticationResources
    class Session < HaveAPI::Resource
      auth false
      version :all

      class Show < HaveAPI::Action
        route ''
        http_method :get
        output(:hash) { string :id }
        authorize { allow }
      end
    end
  end

  class Provider < HaveAPI::Authentication::Basic::Provider
    def resource_module
      AuthenticationResources
    end

    protected

    def find_user(_request, username, password)
      User.new(username) if %w[member admin].include?(username) && password == 'pass'
    end
  end

  class Added < HaveAPI::Resource
    auth false
    version :all

    class Index < HaveAPI::Action
      route ''
      http_method :get
      output(:hash) { string :late }
      authorize { allow }
    end
  end
end

describe HaveAPI::Server, '#mount' do
  api do
    define_resource(:Widget) do
      version :all
      auth false

      define_action(:Show) do
        route '{widget_id}'
        http_method :get
        desc HaveAPI.message('profile_mount_spec.action')
        input(:hash) do
          string :visible
          string :secret, default: 'PRIVATE_DEFAULT'
        end
        output(:hash) do
          string :visible
          string :secret
        end
        authorize do |user|
          unless user.login == 'admin'
            input blacklist: [:secret]
            output blacklist: [:secret]
          end
          allow
        end

        # rubocop:disable RSpec/NoExpectationExample
        example 'visible sample' do
          path_params 7
          request({ visible: 'public sample' })
          response({ visible: 'public response' })
        end

        example 'privileged sample' do
          authorize { |user| user.login == 'admin' }
          path_params 7
          request({ secret: 'PRIVATE_SAMPLE' })
          response({ secret: 'PRIVATE_RESPONSE' })
        end
        # rubocop:enable RSpec/NoExpectationExample
      end

      define_action(:Secret) do
        route 'secret'
        http_method :get
        output(:hash) { string :admin_only }
        authorize { |user| user.login == 'admin' ? allow : deny }
      end
    end
  end

  let(:server) { described_class.new(get_opt(:api_module)) }
  let(:descriptions) { [] }
  let(:contexts) { [] }
  let(:documentation) { Class.new }
  let(:adapter) do
    selected_contexts = contexts
    Class.new do
      define_method(:resolve) { |**| nil }
      define_method(:render) do |kind:, context:, **|
        selected_contexts << context
        { status: :code, code: JSON.generate(kind == :example ? context.sample : { url: context.version_url }) }
      end
    end.new
  end

  before do
    generator = Module.new
    generator.const_set(:VERSION, HaveAPI::VERSION)
    generator.const_set(:Documentation, documentation)
    stub_const('HaveAPI::GoClient', generator)
    allow(registry).to receive(:require).with('haveapi/go_client/documentation').and_return(true)
    allow(documentation).to receive(:new) do |description:, **|
      descriptions << description
      adapter
    end
    server.use_version([1, 2])
    server.default_version = 1
    server.auth_chain << ProfileMountSpec::Provider
  end

  def registry
    server.instance_variable_get(:@documentation_clients)
  end

  def register(version = 1)
    server.documentation_clients(version, go: { import_path: 'example.test/widget/client' })
  end

  def request_as(user, locale)
    Rack::MockRequest.new(server.app).get(
      '/mounted/api/v1/', 'HTTP_HOST' => 'example.org', 'HTTP_ACCEPT_LANGUAGE' => locale,
                          'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64("#{user}:pass")}"
    )
  end

  it 'captures the complete selected version after auth, action-state and post-mount routes exist' do
    register
    server.action_state = Object.new
    server.connect_hook(:post_mount) do |_ret, api_server, _sinatra|
      expect(api_server.documentation_client_profiles(1)).to be_empty
      api_server.mount_resource('/mounted/api/v1/', 1, ProfileMountSpec::Added, api_server.routes[1][:resources])
      {}
    end
    allow(server).to receive(:describe_version).and_call_original
    server.mount('/mounted/api/')
    expect(server).to have_received(:describe_version).once
    expect(descriptions.size).to eq(1)
    private_schema = descriptions.first
    expect(private_schema['help']).to eq('/mounted/api/v1/')
    expect(private_schema['resources'].keys).to include('widget', 'action_state', 'added')
    expect(private_schema.dig('resources', 'widget', 'actions').keys).to include('show', 'secret')
    expect(private_schema.dig('authentication', 'basic', 'resources')).to have_key('session')
    expect(private_schema.dig('resources', 'widget', 'actions', 'show', 'input', 'parameters')).to have_key('secret')
    expect(JSON.generate(private_schema)).not_to include('PRIVATE_DEFAULT', 'PRIVATE_SAMPLE', 'PRIVATE_RESPONSE')
    expect(server.documentation_client_profiles(1).fetch(:go).package_version).to be_nil
    expect(server.documentation_client_profiles(2)).to be_empty
  end

  it 'captures each configured version once and does not initialize from requests' do
    register(1)
    register(2)
    server.mount('/mounted/api/')
    expect(descriptions.map { |description| description['help'] }).to eq(['/mounted/api/v1/', '/mounted/api/v2/'])
    request_as('member', 'en')
    request_as('admin', 'cs')
    expect(descriptions.size).to eq(2)
    expect { register }.to raise_error(HaveAPI::ClientExample::Profiles::Invalid, /already mounted/)
  end

  it 'keeps private schema separate from sequential users, locales, HTML and samples' do
    register
    server.available_locales = %i[en cs]
    ::I18n.backend.store_translations(:en, profile_mount_spec: { action: 'Visible English action' })
    ::I18n.backend.store_translations(:cs, profile_mount_spec: { action: 'Viditelna ceska akce' })
    server.mount('/mounted/api/')
    privileged = request_as('admin', 'en')
    expect(privileged.status).to eq(200)
    expect(privileged.body).to include('PRIVATE_SAMPLE', 'Visible English action')
    contexts.clear
    public_response = request_as('member', 'cs')
    expect(public_response.status).to eq(200)
    expect(public_response.body).to include('Viditelna ceska akce', 'init-go', 'example.test/widget/client')
    expect(public_response.body).not_to include('PRIVATE_DEFAULT', 'PRIVATE_SAMPLE', 'PRIVATE_RESPONSE', 'admin_only', 'haveapi.invalid', 'StructuralSchema')
    selected = contexts.find { |context| context.action_name == 'show' }
    expect(selected.action.dig(:input, :parameters).keys.map(&:to_s)).to eq(['visible'])
    expect(selected.description[:resources]['widget'][:actions]).not_to have_key('secret')
    expect(selected.sample[:request]).to eq(visible: 'public sample')
    expect(selected.action[:description]).to eq('Viditelna ceska akce')
    expect(request_as('member', 'en').body).to include('Visible English action')
    expect(descriptions.size).to eq(1)
  end

  it 'makes the server unusable and publishes no profiles after an adapter failure' do
    register
    allow(documentation).to receive(:new).and_raise('PRIVATE_SCHEMA_DIAGNOSTIC')
    expect { server.mount('/') }.to raise_error(HaveAPI::ClientExample::Profiles::Invalid, 'Configured documentation client schema or configuration is invalid')
    expect(server.app).to be_nil
    expect(server.documentation_client_profiles(1)).to be_empty
  end

  it 'makes the server unusable when a post-mount hook fails before finalization' do
    register
    server.connect_hook(:post_mount) { raise 'fixture mount failure' }
    expect { server.mount('/') }.to raise_error(RuntimeError, 'fixture mount failure')
    expect(documentation).not_to have_received(:new)
    expect(server.app).to be_nil
    expect(server.documentation_client_profiles(1)).to be_empty
  end
end
