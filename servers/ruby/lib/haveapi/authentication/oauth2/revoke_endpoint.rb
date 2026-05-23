require 'rack/oauth2'
require 'rack/auth/basic'

module HaveAPI::Authentication
  module OAuth2
    class RevokeEndpoint < Rack::OAuth2::Server::Abstract::Handler
      def _call(env)
        @request = Request.new(env)
        @request.attr_missing!
        @response = Response.new(request)
        super.finish
      rescue Rack::OAuth2::Server::Abstract::Error => e
        e.finish
      end

      class Request < Rack::OAuth2::Server::Abstract::Request
        attr_required :token
        attr_optional :client_id, :client_secret, :token_type_hint

        def initialize(env)
          auth = Rack::Auth::Basic::Request.new(env)

          if auth.provided? && auth.basic?
            @client_id, @client_secret = auth.credentials.map do |credential|
              Rack::OAuth2::Util.www_form_url_decode(credential)
            end
          end

          super
          @client_secret ||= params['client_secret']
          @token = params['token']
          @token_type_hint = params['token_type_hint']

          invalid_request! unless scalar_request_params?
        rescue ArgumentError, EncodingError
          invalid_request!
        end

        def invalid_client!(description = nil, options = {})
          raise Rack::OAuth2::Server::Token::Unauthorized.new(
            :invalid_client,
            description,
            options
          )
        end

        def invalid_request!(description = nil, options = {})
          raise Rack::OAuth2::Server::Abstract::BadRequest.new(
            :invalid_request,
            description,
            options
          )
        end

        def unsupported_token_type!(description = nil, options = {})
          raise Rack::OAuth2::Server::Abstract::BadRequest.new(
            :unsupported_token_type,
            description,
            options
          )
        end

        private

        def scalar_request_params?
          [client_id, client_secret, token, token_type_hint].all? do |value|
            value.nil? || value.is_a?(String)
          end
        end
      end

      class Response < Rack::OAuth2::Server::Abstract::Response
      end
    end
  end
end
