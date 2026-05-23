# frozen_string_literal: true

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
            authorize { |user| user&.login == 'admin' }
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

    it 'hides examples denied to anonymous users from version docs' do
      header 'Authorization', nil
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
