# frozen_string_literal: true

require 'spec_helper'

module AuthSpecTokenVersionRoutes
  User = Struct.new(:id, :login)

  class << self
    def reset!
      tokens.clear
    end

    def tokens
      @tokens ||= {}
    end
  end

  class LegacyConfig < HaveAPI::Authentication::Token::Config
    request do
      handle do |req, res|
        if req.input[:user] == 'legacy' && req.input[:password] == 'pass'
          AuthSpecTokenVersionRoutes.tokens['legacy-token'] = User.new(1, 'legacy')
          res.token = 'legacy-token'
          res.valid_to = Time.now + 3600
          res.complete = true
          res.ok
        else
          res.error = 'invalid legacy credentials'
          res
        end
      end
    end

    renew do
      handle { |_req, res| res.ok }
    end

    revoke do
      handle { |_req, res| res.ok }
    end

    def find_user_by_token(_request, token)
      AuthSpecTokenVersionRoutes.tokens[token]
    end
  end

  class StrictConfig < HaveAPI::Authentication::Token::Config
    request do
      input do
        string :mfa_code, required: true
      end

      handle do |_req, res|
        res.error = 'strict token issuer reached'
        res
      end
    end

    renew do
      handle { |_req, res| res.ok }
    end

    revoke do
      handle { |_req, res| res.ok }
    end

    def find_user_by_token(_request, token)
      AuthSpecTokenVersionRoutes.tokens[token]
    end
  end

  LegacyProvider = HaveAPI::Authentication::Token.with_config(LegacyConfig)
  StrictProvider = HaveAPI::Authentication::Token.with_config(StrictConfig)

  ApiModule = Module.new do
    def self.define_resource(name, superclass: HaveAPI::Resource, &block)
      cls = Class.new(superclass)
      const_set(name, cls)
      cls.class_exec(&block)
      cls
    end

    define_resource(:Secure) do
      version 2

      define_action(:Ping) do
        route 'ping'
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
end

describe HaveAPI::Authentication::Token do
  let(:api_instance) do
    api = HaveAPI::Server.new(AuthSpecTokenVersionRoutes::ApiModule)
    api.use_version([1, 2])
    api.default_version = 1
    api.auth_chain[1] << AuthSpecTokenVersionRoutes::LegacyProvider
    api.auth_chain[2] << AuthSpecTokenVersionRoutes::StrictProvider
    api.mount('/')
    api
  end

  before do
    AuthSpecTokenVersionRoutes.reset!
    api_instance
  end

  def app
    api_instance.app
  end

  it 'does not mount version-specific token issuers on the shared auth path' do
    call_api(:post, '/_auth/token/tokens', {
      token: {
        user: 'legacy',
        password: 'pass',
        lifetime: 'permanent',
        interval: 60
      }
    })

    expect(last_response.status).to eq(404)
    expect(AuthSpecTokenVersionRoutes.tokens).to be_empty
  end

  it 'routes token requests through the matching API version issuer' do
    call_api(:post, '/v2/_auth/token/tokens', {
      token: {
        user: 'legacy',
        password: 'pass',
        lifetime: 'permanent',
        interval: 60
      }
    })

    expect(last_response.status).to eq(400)
    expect(api_response).to be_failed
    expect(AuthSpecTokenVersionRoutes.tokens).to be_empty

    call_api(:post, '/v1/_auth/token/tokens', {
      token: {
        user: 'legacy',
        password: 'pass',
        lifetime: 'permanent',
        interval: 60
      }
    })

    expect(last_response.status).to eq(200)
    expect(api_response).to be_ok
    expect(api_response[:token][:token]).to eq('legacy-token')
  end
end
