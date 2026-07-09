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

module AuthSpecOAuth2Security
  User = Struct.new(:id, :login)
  AuthResult = Struct.new(:authenticated, :complete, :cancel, :params)

  class Client < HaveAPI::Authentication::OAuth2::Client
    def initialize # rubocop:disable Lint/MissingSuper
      @client_id = 'client'
      @redirect_uri = 'https://client.example/callback'
    end

    def check_secret(client_secret)
      raise TypeError, "client_secret must be a String, got #{client_secret.class}" unless client_secret.is_a?(String)

      client_secret == 'secret'
    end
  end

  class Authorization < HaveAPI::Authentication::OAuth2::Authorization
    def initialize( # rubocop:disable Lint/MissingSuper
      redirect_uri: 'https://client.example/callback',
      code_challenge: nil,
      code_challenge_method: nil
    )
      @redirect_uri = redirect_uri
      @code_challenge = code_challenge
      @code_challenge_method = code_challenge_method
    end

    def check_code_validity(redirect_uri)
      raise TypeError, "redirect_uri must be a String, got #{redirect_uri.class}" unless redirect_uri.is_a?(String)

      redirect_uri == @redirect_uri
    end
  end

  class Config < HaveAPI::Authentication::OAuth2::Config
    class << self
      attr_accessor :authorization
      attr_reader :client_lookups, :revocations

      def reset!
        @authorization = Authorization.new
        @client_lookups = []
        @revocations = []
      end
    end

    def base_url
      'https://api.example'
    end

    def find_user_by_access_token(_request, access_token)
      raise TypeError, "access_token must be a String, got #{access_token.class}" unless access_token.is_a?(String)

      access_token == 'abc' ? User.new(1, 'user') : nil
    end

    def find_client_by_id(client_id)
      raise TypeError, "client_id must be a String, got #{client_id.class}" unless client_id.is_a?(String)

      self.class.client_lookups << client_id
      client_id == 'client' ? Client.new : nil
    end

    def handle_get_authorize(oauth2_request:, **)
      AuthResult.new(true, true, false, oauth2_params(oauth2_request))
    end

    def get_authorization_code(auth_res)
      self.class.authorization = Authorization.new(
        redirect_uri: auth_res.params[:redirect_uri],
        code_challenge: auth_res.params[:code_challenge],
        code_challenge_method: auth_res.params[:code_challenge_method]
      )
      'code'
    end

    def find_authorization_by_code(_client, code)
      raise TypeError, "code must be a String, got #{code.class}" unless code.is_a?(String)

      code == 'code' ? self.class.authorization : nil
    end

    def find_authorization_by_refresh_token(_client, refresh_token)
      raise TypeError, "refresh_token must be a String, got #{refresh_token.class}" unless refresh_token.is_a?(String)

      refresh_token == 'refresh-token' ? Authorization.new : nil
    end

    def get_tokens(_authorization, _request)
      ['access-token', Time.now + 3600, 'refresh-token']
    end

    def refresh_tokens(_authorization, _request)
      ['access-token-2', Time.now + 3600, 'refresh-token-2']
    end

    def handle_post_revoke(_request, token, token_type_hint: nil, client: nil)
      raise TypeError, "token must be a String, got #{token.class}" unless token.is_a?(String)
      if !token_type_hint.nil? && !token_type_hint.is_a?(String)
        raise TypeError, "token_type_hint must be a String, got #{token_type_hint.class}"
      end

      self.class.revocations << {
        token:,
        token_type_hint:,
        client_id: client&.client_id
      }

      token_type_hint == 'unsupported' ? :unsupported : :revoked
    end
  end

  Provider = HaveAPI::Authentication::OAuth2.with_config(Config)
end

describe HaveAPI::Authentication::OAuth2 do
  describe 'smoke' do
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

    it 'returns 400 when bearer and access_token are both provided' do
      header 'Authorization', 'Bearer abc'
      call_api(:post, '/v1/secures/ping?access_token=abc', {})

      expect(last_response.status).to eq(400)
      expect(api_response).to be_failed
      expect(api_response.message).to match(/too many|multiple/i)
    end

    it 'returns 400 when HaveAPI header and access_token are both provided' do
      header 'X-HaveAPI-OAuth2-Token', 'abc'
      call_api(:post, '/v1/secures/ping?access_token=abc', {})

      expect(last_response.status).to eq(400)
      expect(api_response).to be_failed
      expect(api_response.message).to match(/too many|multiple/i)
    end

    it 'localizes multiple token conflicts' do
      header 'Accept-Language', 'cs'
      header 'Authorization', 'Bearer abc'
      call_api(:post, '/v1/secures/ping?access_token=abc', {})

      expect(last_response.status).to eq(400)
      expect(api_response).to be_failed
      expect(api_response.message).to eq('Bylo zadáno více OAuth2 tokenů')
    end

    it 'ignores structured access_token query values before backend lookup' do
      expect do
        call_api(:post, '/v1/secures/ping?access_token[]=abc', {})
      end.not_to raise_error

      expect(last_response.status).to eq(401)
      expect(api_response).to be_failed
    end

    it 'treats malformed bearer headers as failed authentication' do
      invalid = (+"Bearer \xFF").force_encoding(Encoding::UTF_8)
      header 'Authorization', invalid

      call_api(:post, '/v1/secures/ping', {})

      expect(last_response.status).to eq(401)
      expect(api_response).to be_failed
    end

    it 'exposes oauth2 provider in version description' do
      header 'Accept-Language', 'cs'
      call_api(:options, '/v1/')

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok

      auth = api_response[:authentication]
      expect(auth).to have_key(:oauth2)

      desc = auth[:oauth2]
      expect(desc[:description]).to start_with('OAuth2 autorizační provider')
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

  describe 'endpoint hardening' do
    api do
      define_resource(:Secure) do
        version 1

        define_action(:Ping) do
          route 'ping'
          http_method :post
          auth true

          input(:hash) {}
          output(:hash) { integer :user_id }
          authorize { allow }

          def exec
            { user_id: current_user.id }
          end
        end
      end
    end

    default_version 1
    auth_chain AuthSpecOAuth2Security::Provider

    before do
      AuthSpecOAuth2Security::Config.reset!
    end

    def oauth_json
      JSON.parse(last_response.body)
    end

    it 'requires a verifier when a stored PKCE challenge omits the method' do
      AuthSpecOAuth2Security::Config.authorization =
        AuthSpecOAuth2Security::Authorization.new(code_challenge: 'expected-verifier')

      post '/_auth/oauth2/token', {
        grant_type: 'authorization_code',
        code: 'code',
        redirect_uri: 'https://client.example/callback',
        client_id: 'client',
        client_secret: 'secret'
      }

      expect(last_response.status).to eq(400)
      expect(oauth_json['error']).to eq('invalid_grant')

      post '/_auth/oauth2/token', {
        grant_type: 'authorization_code',
        code: 'code',
        redirect_uri: 'https://client.example/callback',
        client_id: 'client',
        client_secret: 'secret',
        code_verifier: 'expected-verifier'
      }

      expect(last_response.status).to eq(200)
      expect(oauth_json['access_token']).to eq('access-token')
    end

    it 'preserves omitted PKCE methods as plain in authorization params' do
      get '/_auth/oauth2/authorize', {
        response_type: 'code',
        client_id: 'client',
        redirect_uri: 'https://client.example/callback',
        code_challenge: 'expected-verifier'
      }

      expect(last_response.status).to eq(302)
      authorization = AuthSpecOAuth2Security::Config.authorization
      expect(authorization.code_challenge).to eq('expected-verifier')
      expect(authorization.code_challenge_method).to eq('plain')
    end

    it 'rejects structured authorization endpoint parameters' do
      [
        { response_type: 'code', 'client_id' => ['client'], redirect_uri: 'https://client.example/callback' },
        { response_type: 'code', client_id: 'client', 'redirect_uri' => ['https://client.example/callback'] },
        {
          response_type: 'code',
          client_id: 'client',
          redirect_uri: 'https://client.example/callback',
          code_challenge: 'expected-verifier',
          'code_challenge_method' => ['plain']
        }
      ].each do |request_params|
        AuthSpecOAuth2Security::Config.client_lookups.clear
        get '/_auth/oauth2/authorize', request_params

        expect(last_response.status).to eq(400)
        expect(oauth_json['error']).to eq('invalid_request')
        expect(AuthSpecOAuth2Security::Config.client_lookups).to be_empty
      end
    end

    it 'returns controlled errors for authorization protocol failures' do
      get '/_auth/oauth2/authorize', {
        response_type: 'code',
        redirect_uri: 'https://client.example/callback'
      }

      expect(last_response.status).to eq(400)
      expect(oauth_json['error']).to eq('invalid_request')

      get '/_auth/oauth2/authorize', {
        response_type: 'bogus',
        client_id: 'client',
        redirect_uri: 'https://client.example/callback'
      }

      expect(last_response.status).to eq(400)
      expect(oauth_json['error']).to eq('unsupported_response_type')
    end

    it 'rejects structured token endpoint parameters before callbacks' do
      [
        { grant_type: 'authorization_code', 'client_id' => ['client'], client_secret: 'secret', code: 'code' },
        { grant_type: 'authorization_code', client_id: 'client', 'client_secret' => ['secret'], code: 'code' },
        { grant_type: 'authorization_code', client_id: 'client', client_secret: 'secret', 'code' => ['code'] },
        {
          grant_type: 'authorization_code',
          client_id: 'client',
          client_secret: 'secret',
          code: 'code',
          'redirect_uri' => ['https://client.example/callback']
        },
        { grant_type: 'refresh_token', client_id: 'client', client_secret: 'secret', 'refresh_token' => ['refresh-token'] },
        { grant_type: 'authorization_code', client_id: 'client', client_secret: 'secret', code: 'code', 'code_verifier' => ['verifier'] }
      ].each do |request_params|
        AuthSpecOAuth2Security::Config.client_lookups.clear
        post '/_auth/oauth2/token', request_params

        expect(last_response.status).to eq(400)
        expect(oauth_json['error']).to eq('invalid_request')
        expect(AuthSpecOAuth2Security::Config.client_lookups).to be_empty
      end
    end

    it 'requires OAuth2 client authentication before revocation' do
      post '/_auth/oauth2/revoke', {
        token: 'victim-refresh-token',
        token_type_hint: 'refresh_token'
      }

      expect(last_response.status).to eq(401)
      expect(oauth_json['error']).to eq('invalid_client')
      expect(AuthSpecOAuth2Security::Config.revocations).to be_empty
    end

    it 'rejects malformed revoke requests before callbacks' do
      [
        { token_type_hint: 'access_token', client_id: 'client', client_secret: 'secret' },
        { 'token' => ['abc'], client_id: 'client', client_secret: 'secret' },
        { token: 'abc', 'token_type_hint' => ['refresh_token'], client_id: 'client', client_secret: 'secret' }
      ].each do |request_params|
        post '/_auth/oauth2/revoke', request_params

        expect(last_response.status).to eq(400)
        expect(oauth_json['error']).to eq('invalid_request')
        expect(AuthSpecOAuth2Security::Config.revocations).to be_empty
      end
    end

    it 'revokes only after valid client authentication' do
      post '/_auth/oauth2/revoke', {
        token: 'victim-refresh-token',
        token_type_hint: 'refresh_token',
        client_id: 'client',
        client_secret: 'secret'
      }

      expect(last_response.status).to eq(200)
      expect(AuthSpecOAuth2Security::Config.revocations).to contain_exactly(
        {
          token: 'victim-refresh-token',
          token_type_hint: 'refresh_token',
          client_id: 'client'
        }
      )
    end

    it 'returns OAuth2 errors for unsupported revoke token hints' do
      post '/_auth/oauth2/revoke', {
        token: 'victim-refresh-token',
        token_type_hint: 'unsupported',
        client_id: 'client',
        client_secret: 'secret'
      }

      expect(last_response.status).to eq(400)
      expect(oauth_json['error']).to eq('unsupported_token_type')
    end
  end
end
