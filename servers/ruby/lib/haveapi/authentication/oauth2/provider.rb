require 'haveapi/authentication/base'
require 'rack/oauth2'

module HaveAPI::Authentication
  module OAuth2
    # Abstract class describing the client and what methods it must respond to
    class Client
      # @return [String]
      attr_reader :client_id

      # @return [String]
      attr_reader :redirect_uri

      # @param client_secret [String]
      # @return [Boolean]
      def check_secret(client_secret)
        raise NotImplementedError
      end
    end

    # Abstract class describing the authentication result and what methods it must respond to
    class AuthResult
      # True of the user was authenticated
      # @return [Boolean]
      attr_reader :authenticated

      # True if the authentication process is complete, false if other steps are needed
      # @return [Boolean]
      attr_reader :complete

      # True if the user asked to cancel the authorization process
      # @return [Boolean]
      attr_reader :cancel
    end

    # Abstract class describing ongoing authorization and what methods it must respond to
    class Authorization
      # @return [String, nil]
      attr_reader :code_challenge

      # @return [String, nil]
      attr_reader :code_challenge_method

      # @return [String]
      attr_reader :redirect_uri

      # @param redirect_uri [String]
      # @return [Boolean]
      def check_code_validity(redirect_uri)
        raise NotImplementedError
      end
    end

    # OAuth2 authentication and authorization provider
    #
    # Must be configured with {Config} using {OAuth2.with_config}.
    class Provider < Base
      auth_method :oauth2

      # Configure the OAuth2 provider
      # @param cfg [Config]
      def self.with_config(cfg)
        Module.new do
          define_singleton_method(:new) do |*args|
            Provider.new(*args, cfg)
          end
        end
      end

      # @return [String]
      attr_reader :authorize_path

      # @return [Config]
      attr_reader :config

      def initialize(server, v, cfg)
        @config = cfg.new(self, server, v)
        super(server, v)
      end

      def register_routes(sinatra, prefix)
        @authorize_path = File.join(prefix, 'authorize')
        @token_path = File.join(prefix, 'token')
        @revoke_path = File.join(prefix, 'revoke')
        that = self

        sinatra.get @authorize_path do
          that.authorization_endpoint(self).call(request.env)
        end

        sinatra.post @authorize_path do
          that.authorization_endpoint(self).call(request.env)
        end

        sinatra.post @token_path do
          that.token_endpoint(self).call(request.env)
        end

        sinatra.post @revoke_path do
          that.revoke_endpoint(self).call(request.env)
        end
      end

      def authenticate(request)
        tokens = [
          request['access_token'],
          token_from_header(request)
        ].compact

        token =
          case tokens.length
          when 0
            nil
          when 1
            tokens.first
          else
            fail 'Too many oauth2 tokens'
          end

        token && config.find_user_by_access_token(request, token)
      end

      def token_from_header(request)
        auth_header = Rack::Auth::AbstractRequest.new(request.env)

        if auth_header.provided? && !auth_header.parts.first.nil? && auth_header.scheme.to_s == 'bearer'
          auth_header.params
        else
          nil
        end
      end

      def describe
        desc = <<-END
        OAuth2 authorization provider. While OAuth2 is not supported by HaveAPI
        clients, it is possible to use your API as an authentication source.

        HaveAPI partially implements RFC 6749: authorization response type "code"
        and token grant types "authorization_code" and "refresh_token". Other
        response and grant types are not supported at this time.

        The access token can be passed as bearer token according to RFC 6750.

        The access and refresh tokens can be revoked as per RFC 7009.
        END

        {
          description: desc,
          authorize_path: @authorize_path,
          token_path: @token_path,
          revoke_path: @revoke_path,
        }
      end

      def authorization_endpoint(handler)
        Rack::OAuth2::Server::Authorize.new do |req, res|
          client = config.find_client_by_id(req.client_id)
          req.bad_request! if client.nil?

          res.redirect_uri = req.verify_redirect_uri!(client.redirect_uri)

          if req.post?
            auth_res = config.handle_post_authorize(handler.request, handler.params, req, client)

            if auth_res.nil?
              # Authentication failed
              req.access_denied!
            elsif auth_res.cancel
              # Cancel the process
              req.access_denied!
            elsif auth_res.authenticated && auth_res.complete
              # Authentication was successful
              case req.response_type
              when :code
                res.code = config.get_authorization_code(auth_res)
              when :token
                req.unsupported_response_type!
              end

              res.approve!
            elsif auth_res.authenticated && !auth_res.complete
              # Continue with another authentication step
              res.content_type = 'text/html'
              res.write(config.render_authorize_page(req, handler.params, client, auth_result: auth_res))
            else
              # Authentication failed, report errors and let the user retry
              res.content_type = 'text/html'
              res.write(config.render_authorize_page(req, handler.params, client, auth_result: auth_res))
            end
          else
            res.content_type = 'text/html'
            res.write(config.render_authorize_page(req, handler.params, client))
          end
        end
      end

      def token_endpoint(handler)
        Rack::OAuth2::Server::Token.new do |req, res|
          client = config.find_client_by_id(req.client_id)
          req.invalid_client! if client.nil? || !client.check_secret(req.client_secret)

          res.access_token =
            case req.grant_type
            when :authorization_code
              authorization = config.find_authorization_by_code(client, req.code)

              if authorization.nil? || !authorization.check_code_validity(req.redirect_uri)
                req.invalid_grant!
              end

              if authorization.code_challenge && authorization.code_challenge_method
                req.verify_code_verifier!(
                  authorization.code_challenge,
                  authorization.code_challenge_method.to_sym,
                )
              end

              access_token, expires_at, refresh_token = config.get_tokens(authorization, handler.request)

              bearer_token = Rack::OAuth2::AccessToken::Bearer.new(
                access_token: access_token,
                expires_in: expires_at - Time.now,
              )
              bearer_token.refresh_token = refresh_token if refresh_token
              bearer_token

            when :password
              req.unsupported_grant_type!

            when :client_credentials
              req.unsupported_grant_type!

            when :refresh_token
              config.find_authorization_by_refresh_token(client, req.refresh_token)

              access_token, expires_at, refresh_token = config.refresh_tokens(authorization, handler.request)

              bearer_token = Rack::OAuth2::AccessToken::Bearer.new(
                access_token: access_token,
                expires_in: expires_at - Time.now,
              )
              bearer_token.refresh_token = refresh_token if refresh_token
              bearer_token

            else
              req.unsupported_grant_type!
            end
        end
      end

      def revoke_endpoint(handler)
        RevokeEndpoint.new do |req, res|
          ret = config.handle_post_revoke(
            handler.request,
            req.token,
            token_type_hint: req.token_type_hint,
          )

          case ret
          when :revoked
            # ok
          when :unsupported
            req.unsupported_token_type!
          else
            raise Rack::OAuth2::Server::Abstract::ServerError
          end
        end
      end
    end
  end
end
