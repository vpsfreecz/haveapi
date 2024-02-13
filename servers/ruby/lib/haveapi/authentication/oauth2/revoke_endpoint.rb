require 'rack/oauth2'

module HaveAPI::Authentication
  module OAuth2
    class RevokeEndpoint < Rack::OAuth2::Server::Abstract::Handler
      def _call(env)
        @request  = Request.new(env)
        @response = Response.new(request)
        super
      end

      class Request < Rack::OAuth2::Server::Abstract::Request
        attr_required :token
        attr_optional :token_type_hint

        def initialize(env)
          super
          @token = params['token']
          @token_type_hint = params['token_type_hint']
        end

        def unsupported_token_type!(description = nil, options = {})
          raise Rack::OAuth2::Server::Abstract::BadRequest.new(
            :unsupported_token_type,
            description,
            options
          )
        end
      end

      class Response < Rack::OAuth2::Server::Abstract::Response
      end
    end
  end
end
