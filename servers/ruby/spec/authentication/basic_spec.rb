# frozen_string_literal: true

require 'spec_helper'

module AuthSpecBasic
  User = Struct.new(:id, :login)

  class Provider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, username, password)
      return User.new(1, username) if username == 'user' && password == 'pass'
      return nil unless username == 'error'

      # Exercise the rescue path in Basic::Provider#authenticate
      raise HaveAPI::AuthenticationError, 'backend failed'
    end
  end
end

describe HaveAPI::Authentication::Basic::Provider do
  api do
    define_resource(:Secure) do
      version 1
      desc 'Secured resource'

      define_action(:Ping) do
        route 'ping'
        http_method :post
        auth true

        input(:hash) do
          # accept empty JSON body
        end

        output(:hash) do
          integer :user_id
          string :login
        end

        authorize { allow }

        def exec
          {
            user_id: current_user.id,
            login: current_user.login
          }
        end
      end
    end
  end

  default_version 1
  auth_chain AuthSpecBasic::Provider

  let(:seen_users) { [] }
  let(:api_instance) do
    app
    instance_variable_get(:@api)
  end

  before do
    api_instance.connect_hook(:post_authenticated) do |ret, current_user|
      seen_users << current_user
      ret
    end
  end

  it 'returns 401 without credentials' do
    call_api(:post, '/v1/secures/ping', {})

    expect(last_response.status).to eq(401)
    expect(last_response.headers['www-authenticate']).to include('Basic realm=')

    expect(api_response).to be_failed
    expect(api_response.message).to include('authenticate')
    expect(seen_users.last).to be_nil
  end

  it 'returns 401 with wrong credentials' do
    login('user', 'wrong')
    call_api(:post, '/v1/secures/ping', {})

    expect(last_response.status).to eq(401)
    expect(api_response).to be_failed
    expect(seen_users.last).to be_nil
  end

  it 'authenticates with correct credentials' do
    login('user', 'pass')
    call_api(:post, '/v1/secures/ping', {})

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:secure][:user_id]).to eq(1)
    expect(api_response[:secure][:login]).to eq('user')
    expect(seen_users.last).to be_a(AuthSpecBasic::User)
  end

  it 'handles AuthenticationError raised by backend' do
    login('error', 'pass')
    call_api(:post, '/v1/secures/ping', {})

    expect(last_response.status).to eq(401)
    expect(api_response).to be_failed
    expect(seen_users.last).to be_nil
  end
end
