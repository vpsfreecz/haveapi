# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

describe 'Authentication: Token' do
  module AuthSpecToken
    User = Struct.new(:id, :login)

    class Config < HaveAPI::Authentication::Token::Config
      class << self
        def reset!
          @tokens = {}
        end

        def tokens
          @tokens ||= {}
        end
      end

      request do
        handle do |req, res|
          input = req.input

          if input[:user] == 'user' && input[:password] == 'pass'
            token = "t-#{SecureRandom.hex(8)}"
            user = User.new(1, 'user')
            Config.tokens[token] = user

            res.token = token
            res.valid_to = Time.now + input[:interval].to_i
            res.complete = true
            res.ok
          else
            res.error = 'invalid credentials'
            res
          end
        end
      end

      renew do
        handle do |_req, res|
          res.valid_to = Time.now + 3600
          res.ok
        end
      end

      revoke do
        handle do |req, res|
          Config.tokens.delete(req.token)
          res.ok
        end
      end

      def find_user_by_token(_request, token)
        self.class.tokens[token]
      end
    end

    Provider = HaveAPI::Authentication::Token.with_config(Config)
  end

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
  auth_chain AuthSpecToken::Provider

  before(:each) do
    AuthSpecToken::Config.reset!
    app
  end

  def request_token!
    call_api(:post, '/_auth/token/tokens', {
      token: {
        user: 'user',
        password: 'pass',
        lifetime: 'permanent',
        interval: 60,
        scope: 'all'
      }
    })

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    api_response[:token][:token]
  end

  it 'allows token request without authentication' do
    call_api(:post, '/_auth/token/tokens', {
      token: {
        user: 'user',
        password: 'pass',
        lifetime: 'permanent',
        interval: 60
      }
    })

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:token][:token]).to be_a(String)
  end

  it 'returns 401 for protected action without token' do
    call_api(:post, '/v1/secures/ping', {})

    expect(last_response.status).to eq(401)
    expect(api_response).to be_failed
  end

  it 'authenticates using token HTTP header' do
    token = request_token!
    header AuthSpecToken::Config.http_header, token

    call_api(:post, '/v1/secures/ping', {})
    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:secure][:user_id]).to eq(1)
  end

  it 'authenticates using token query parameter' do
    token = request_token!
    param = AuthSpecToken::Config.query_parameter.to_s

    call_api(:post, "/v1/secures/ping?#{param}=#{token}", {})
    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:secure][:user_id]).to eq(1)
  end

  it 'requires authentication for renew and revoke endpoints' do
    call_api(:post, '/_auth/token/tokens/renew', {})
    expect(last_response.status).to eq(401)

    call_api(:post, '/_auth/token/tokens/revoke', {})
    expect(last_response.status).to eq(401)
  end

  it 'renews and revokes token and then token stops working' do
    token = request_token!
    header AuthSpecToken::Config.http_header, token

    call_api(:post, '/_auth/token/tokens/renew', {})
    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:token][:valid_to]).not_to be_nil

    header AuthSpecToken::Config.http_header, token
    call_api(:post, '/_auth/token/tokens/revoke', {})
    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    header AuthSpecToken::Config.http_header, token
    call_api(:post, '/v1/secures/ping', {})
    expect(last_response.status).to eq(401)
  end

  it 'requires auth for OPTIONS on revoke path, but not on request path' do
    call_api(:options, '/_auth/token/tokens?method=POST')
    expect(last_response.status).to eq(200)

    call_api(:options, '/_auth/token/tokens/revoke?method=POST')
    expect(last_response.status).to eq(401)

    token = request_token!
    header AuthSpecToken::Config.http_header, token
    call_api(:options, '/_auth/token/tokens/revoke?method=POST')
    expect(last_response.status).to eq(200)
  end

  it 'exposes token provider in version description' do
    call_api(:options, '/v1/')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    auth = api_response[:authentication]
    expect(auth).to have_key(:token)
    expect(auth[:token][:http_header]).to eq(AuthSpecToken::Config.http_header)
    expect(auth[:token][:query_parameter]).to eq(AuthSpecToken::Config.query_parameter.to_s)

    expect(auth[:token]).to have_key(:resources)
    expect(auth[:token][:resources]).to have_key(:token)
  end
end
