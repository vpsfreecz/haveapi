# frozen_string_literal: true

# rubocop:disable RSpec/InstanceVariable, RSpec/MultipleDescribes

require 'spec_helper'

module DocAuthFilteringSpec
  User = Struct.new(:id, :login)

  class BasicProvider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, username, password)
      return User.new(1, username) if %w[user admin].include?(username) && password == 'pass'

      nil
    end
  end
end

module DocAuthProviderResourceSpec
  class Provider < HaveAPI::Authentication::Base
    auth_method :secret_auth

    def resource_module
      Resources
    end

    def authenticate(_request)
      :user
    end
  end

  module Resources
    class HiddenToken < HaveAPI::Resource
      desc 'Internal authentication resource'
      auth false
      version :all

      class Show < HaveAPI::Action
        route '{hidden_token_id}'

        output(:hash) do
          string :id
        end

        authorize { deny }
      end
    end
  end
end

module CrossVersionDocAuthSpec
  User = Struct.new(:login)

  class V1Provider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, username, password)
      User.new(username) if username == 'v1-user' && password == 'pass'
    end
  end

  class V2Provider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, _username, _password)
      nil
    end
  end

  ApiModule = Module.new do
    def self.define_resource(name, superclass: HaveAPI::Resource, &block)
      cls = Class.new(superclass)
      const_set(name, cls)
      cls.class_exec(&block)
      cls
    end

    define_resource(:Public) do
      version 1
      route 'publics'

      define_action(:Ping) do
        route 'ping'
        http_method :get
        auth true

        output(:hash) do
          string :msg
        end

        authorize { |user| user ? allow : deny }

        def exec
          { msg: 'v1' }
        end
      end
    end

    define_resource(:Secret) do
      version 2
      route 'secrets'

      define_action(:Reveal) do
        route 'reveal'
        http_method :get
        auth true

        input(:hash) do
          string :internal_ticket, required: true
        end

        output(:hash) do
          string :secret_material
        end

        authorize { |user| user ? allow : deny }

        def exec
          { secret_material: 'v2' }
        end
      end
    end
  end
end

describe DocAuthFilteringSpec do
  context 'when viewing documentation' do
    api do
      define_resource(:Secure) do
        version 1
        desc 'Secure test resource'

        define_action(:Public) do
          route 'public'
          http_method :get
          auth false

          output(:hash) { string :msg }
          authorize { allow }

          # rubocop:disable RSpec/NoExpectationExample
          example 'admin-only public result' do
            authorize { |user| user.login == 'admin' }
            response({ msg: 'ADMIN_ONLY_RESULT' })
          end
          # rubocop:enable RSpec/NoExpectationExample

          def exec
            { msg: 'public' }
          end
        end

        define_action(:Private) do
          route 'private'
          http_method :get
          auth true

          output(:hash) { string :msg }
          authorize { allow }

          def exec
            { msg: 'private' }
          end
        end

        define_resource(:HiddenChild) do
          desc 'Hidden nested resource'
          auth false

          define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
            authorize { deny }
          end
        end
      end
    end

    default_version 1
    auth_chain DocAuthFilteringSpec::BasicProvider

    it 'includes auth-required actions in version docs for anonymous' do
      header 'Authorization', nil
      call_api(:options, '/v1/')

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok

      resources = api_response[:resources]
      secure = resources[:secure]
      actions = secure[:actions]

      expect(actions).to have_key(:public)
      expect(actions).to have_key(:private)
    end

    it 'includes auth-required actions in version docs for authenticated' do
      login('user', 'pass')
      call_api(:options, '/v1/')

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok

      resources = api_response[:resources]
      secure = resources[:secure]
      actions = secure[:actions]

      expect(actions).to have_key(:public)
      expect(actions).to have_key(:private)
    end

    it 'prunes nested resources with no authorized actions or children' do
      login('user', 'pass')
      call_api(:options, '/v1/')

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response[:resources][:secure][:resources]).not_to have_key(:hidden_child)
    end

    it 'restricts action documentation for private actions' do
      header 'Authorization', nil
      call_api(:options, '/v1/secures/private?method=GET')

      expect(last_response.status).to be_in([401, 404])
      expect(api_response).to be_failed

      login('user', 'pass')
      call_api(:options, '/v1/secures/private?method=GET')

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response[:method]).to eq('GET')
    end

    it 'allows public action documentation without auth' do
      header 'Authorization', nil
      call_api(:options, '/v1/secures/public?method=GET')

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response[:method]).to eq('GET')
    end

    it 'includes examples for anonymous version docs without evaluating example auth' do
      header 'Authorization', nil
      call_api(:options, '/v1/')

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok

      examples = api_response[:resources][:secure][:actions][:public][:examples]
      expect(examples.size).to eq(1)
      expect(examples.first[:response][:msg]).to eq('ADMIN_ONLY_RESULT')
    end

    it 'hides examples denied to authenticated users from version docs' do
      login('user', 'pass')
      call_api(:options, '/v1/')

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok

      examples = api_response[:resources][:secure][:actions][:public][:examples]
      expect(examples).to be_empty
    end

    it 'shows examples allowed to authenticated users in version docs' do
      login('admin', 'pass')
      call_api(:options, '/v1/')

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok

      examples = api_response[:resources][:secure][:actions][:public][:examples]
      expect(examples.size).to eq(1)
      expect(examples.first[:response][:msg]).to eq('ADMIN_ONLY_RESULT')
    end
  end
end

describe DocAuthProviderResourceSpec do
  empty_api
  use_version 1
  auth_chain DocAuthProviderResourceSpec::Provider

  it 'prunes provider resources with no authorized actions or children' do
    call_api(:options, '/v1/')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:authentication][:secret_auth][:resources]).to be_empty
  end
end

describe CrossVersionDocAuthSpec do
  before do
    @api = HaveAPI::Server.new(CrossVersionDocAuthSpec::ApiModule)
    @api.use_version([1, 2])
    @api.default_version = 1
    @api.auth_chain[1] << CrossVersionDocAuthSpec::V1Provider
    @api.auth_chain[2] << CrossVersionDocAuthSpec::V2Provider
    @api.mount('/')
  end

  it 'does not describe versions that reject the supplied credentials' do
    login('v1-user', 'pass')
    call_api(:options, '/')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:versions]).to have_key(:'1')
    expect(api_response[:versions]).not_to have_key(:'2')
  end
end

# rubocop:enable RSpec/InstanceVariable, RSpec/MultipleDescribes
