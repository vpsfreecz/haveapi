# frozen_string_literal: true

require 'spec_helper'

module AuthSpecOAuth2
  User = Struct.new(:id, :login)

  class Config < HaveAPI::Authentication::OAuth2::Config
    def base_url
      'https://example.test'
    end

    def find_user_by_access_token(_request, access_token)
      access_token == 'abc' ? User.new(1, 'user') : nil
    end
  end

  Provider = HaveAPI::Authentication::OAuth2.with_config(Config)
end

describe HaveAPI::Authentication::OAuth2, 'smoke' do

  api do
    define_resource(:Secure) do
      version 1
      desc 'Secured resource'

      define_action(:Ping) do
        route 'ping'
        http_method :post
        auth true

        input(:hash) do
        end

        output(:hash) do
          integer :user_id
        end

        authorize { allow }

        def exec
          { user_id: current_user.id }
        end
      end
    end
  end

  default_version 1
  auth_chain AuthSpecOAuth2::Provider

  before do
    app
  end

  it 'returns 401 without oauth2 token' do
    call_api(:post, '/v1/secures/ping', {})
    expect(last_response.status).to eq(401)
  end

  it 'authenticates with Authorization: Bearer token' do
    header 'Authorization', 'Bearer abc'
    call_api(:post, '/v1/secures/ping', {})

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:secure][:user_id]).to eq(1)
  end

  it 'authenticates with access_token query parameter' do
    call_api(:post, '/v1/secures/ping?access_token=abc', {})

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:secure][:user_id]).to eq(1)
  end

  it 'authenticates with custom HaveAPI OAuth2 header' do
    header 'X-HaveAPI-OAuth2-Token', 'abc'
    call_api(:post, '/v1/secures/ping', {})

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:secure][:user_id]).to eq(1)
  end

  it 'exposes oauth2 provider in version description' do
    call_api(:options, '/v1/')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    auth = api_response[:authentication]
    expect(auth).to have_key(:oauth2)

    desc = auth[:oauth2]
    expect(desc).to have_key(:http_header)
    expect(desc[:http_header]).to eq('X-HaveAPI-OAuth2-Token')

    expect(desc[:authorize_path]).to include('/_auth/oauth2/authorize')
    expect(desc[:token_path]).to include('/_auth/oauth2/token')
    expect(desc[:revoke_path]).to include('/_auth/oauth2/revoke')

    expect(desc[:authorize_url]).to end_with(desc[:authorize_path])
    expect(desc[:token_url]).to end_with(desc[:token_path])
    expect(desc[:revoke_url]).to end_with(desc[:revoke_path])
  end
end
