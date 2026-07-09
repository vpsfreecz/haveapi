# frozen_string_literal: true

# rubocop:disable RSpec/MultipleDescribes
# rubocop:disable RSpec/RepeatedExampleGroupDescription

require 'spec_helper'
require 'securerandom'

module AuthSpecToken
  User = Struct.new(:id, :login)

  class Config < HaveAPI::Authentication::Token::Config
    class << self
      attr_accessor :raise_on_find, :raise_on_renew, :raise_on_revoke

      def reset!
        @tokens = {}
        @raise_on_find = false
        @raise_on_renew = false
        @raise_on_revoke = false
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
        raise HaveAPI::AuthenticationError, 'renew rejected' if Config.raise_on_renew

        res.valid_to = Time.now + 3600
        res.ok
      end
    end

    revoke do
      handle do |req, res|
        raise HaveAPI::AuthenticationError, 'revoke rejected' if Config.raise_on_revoke

        Config.tokens.delete(req.token)
        res.ok
      end
    end

    def find_user_by_token(_request, token)
      raise TypeError, "token must be a String, got #{token.class}" unless token.is_a?(String)
      raise HaveAPI::AuthenticationError, 'backend rejected token' if self.class.raise_on_find

      self.class.tokens[token]
    end
  end

  Provider = HaveAPI::Authentication::Token.with_config(Config)
end

describe HaveAPI::Authentication::Token do
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

  before do
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

  it 'rejects token request intervals outside policy bounds' do
    [-1, 0, 86_401].each do |interval|
      call_api(:post, '/_auth/token/tokens', {
        token: {
          user: 'user',
          password: 'pass',
          lifetime: 'fixed',
          interval:
        }
      })

      expect(last_response.status).to eq(400)
      expect(api_response).to be_failed
      expect(api_response.errors[:interval]).not_to be_empty
    end
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

  it 'returns 400 when token is provided in multiple places' do
    token = request_token!
    param = AuthSpecToken::Config.query_parameter.to_s

    header AuthSpecToken::Config.http_header, token
    call_api(:post, "/v1/secures/ping?#{param}=#{token}", {})

    expect(last_response.status).to eq(400)
    expect(api_response).to be_failed
    expect(api_response.message).to match(/too many|multiple/i)
  end

  it 'ignores structured token query values before backend lookup' do
    expect do
      call_api(:post, '/v1/secures/ping?_auth_token[]=abc', {})
    end.not_to raise_error

    expect(last_response.status).to eq(401)
    expect(api_response).to be_failed
  end

  it 'treats AuthenticationError from token lookup as failed authentication' do
    token = request_token!
    AuthSpecToken::Config.raise_on_find = true

    header AuthSpecToken::Config.http_header, token
    call_api(:post, '/v1/secures/ping', {})

    expect(last_response.status).to eq(401)
    expect(api_response).to be_failed
  end

  it 'returns 400 for revoke when multiple tokens are provided' do
    token = request_token!
    param = AuthSpecToken::Config.query_parameter.to_s

    header AuthSpecToken::Config.http_header, token
    call_api(:post, "/_auth/token/tokens/revoke?#{param}=#{token}", {})

    expect(last_response.status).to eq(400)
    expect(api_response).to be_failed
    expect(api_response.message).to match(/too many|multiple/i)
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

  it 'returns controlled errors when renew and revoke handlers reject authentication' do
    token = request_token!

    AuthSpecToken::Config.raise_on_renew = true
    header AuthSpecToken::Config.http_header, token
    call_api(:post, '/_auth/token/tokens/renew', {})

    expect(last_response.status).to eq(200)
    expect(api_response).to be_failed
    expect(api_response.message).to eq('renew rejected')

    AuthSpecToken::Config.raise_on_renew = false
    AuthSpecToken::Config.raise_on_revoke = true
    header AuthSpecToken::Config.http_header, token
    call_api(:post, '/_auth/token/tokens/revoke', {})

    expect(last_response.status).to eq(200)
    expect(api_response).to be_failed
    expect(api_response.message).to eq('revoke rejected')
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
    header 'Accept-Language', 'cs'
    call_api(:options, '/v1/')

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok

    auth = api_response[:authentication]
    expect(auth).to have_key(:token)
    expect(auth[:token][:description]).to start_with('Klient se autentizuje')
    expect(auth[:token][:http_header]).to eq(AuthSpecToken::Config.http_header)
    expect(auth[:token][:query_parameter]).to eq(AuthSpecToken::Config.query_parameter.to_s)

    expect(auth[:token]).to have_key(:resources)
    expect(auth[:token][:resources]).to have_key(:token)

    resource = auth[:token][:resources][:token]
    expect(resource[:description]).to eq('Spravovat autentizační tokeny')
    expect(resource[:actions][:request][:description]).to eq('Vyžádat autentizační token')
    expect(resource[:actions][:revoke][:description]).to eq('Zneplatnit aktuální autentizační token')
    expect(resource[:actions][:renew][:description]).to eq('Obnovit aktuální autentizační token')
  end
end

module AuthSpecTokenCrossProvider
  User = Struct.new(:id, :login)

  class << self
    def reset!
      tokens.replace(
        'victim-token' => User.new(1, 'victim'),
        'attacker-token' => User.new(2, 'attacker')
      )
      revoked.clear
    end

    def tokens
      @tokens ||= {}
    end

    def revoked
      @revoked ||= []
    end
  end

  class BasicProvider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, username, password)
      return User.new(2, 'attacker') if username == 'attacker' && password == 'pass'

      nil
    end
  end

  class TokenConfig < HaveAPI::Authentication::Token::Config
    request do
      handle do |_req, res|
        res.error = 'not used'
        res
      end
    end

    renew do
      handle do |_req, res|
        res.ok
      end
    end

    revoke do
      handle do |req, res|
        AuthSpecTokenCrossProvider.revoked << {
          current_user: req.user.login,
          token: req.token
        }
        AuthSpecTokenCrossProvider.tokens.delete(req.token)
        res.ok
      end
    end

    def find_user_by_token(_request, token)
      AuthSpecTokenCrossProvider.tokens[token]
    end
  end

  TokenProvider = HaveAPI::Authentication::Token.with_config(TokenConfig)
end

describe HaveAPI::Authentication::Token do
  api do
    define_resource(:Secure) do
      version 1

      define_action(:Whoami) do
        route 'whoami'
        http_method :post
        auth true

        input(:hash) {}
        output(:hash) { string :login }
        authorize { allow }

        def exec
          { login: current_user.login }
        end
      end
    end
  end

  default_version 1
  auth_chain [
    AuthSpecTokenCrossProvider::BasicProvider,
    AuthSpecTokenCrossProvider::TokenProvider
  ]

  before do
    AuthSpecTokenCrossProvider.reset!
  end

  it 'uses the token provider user for renew and revoke actions' do
    login('attacker', 'pass')
    call_api(:post, '/_auth/token/tokens/revoke?_auth_token=victim-token', {})

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(AuthSpecTokenCrossProvider.revoked).to contain_exactly(
      {
        current_user: 'victim',
        token: 'victim-token'
      }
    )
  end

  it 'rejects token actions authenticated only by another provider' do
    login('attacker', 'pass')
    call_api(:post, '/_auth/token/tokens/revoke', {})

    expect(last_response.status).to eq(401)
    expect(api_response).to be_failed
    expect(AuthSpecTokenCrossProvider.revoked).to be_empty
  end
end

# rubocop:enable RSpec/RepeatedExampleGroupDescription
# rubocop:enable RSpec/MultipleDescribes
