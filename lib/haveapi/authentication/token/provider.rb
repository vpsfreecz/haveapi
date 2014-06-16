module HaveAPI::Authentication
  module Token
    # Exception that has to be raised when generated token already exists.
    # Provider will catch it and generate another token.
    class TokenExists < Exception

    end

    # Provider for token authentication. This class has to be subclassed
    # and implemented.
    #
    # Token auth contains resource token. User can request a token by calling
    # action Resources::Token::Request. Returned token is then used for
    # authenticating the user. Client sends the token with each request
    # in configured #http_header or #query_parameter.
    #
    # Token can be revoked by calling Resources::Token::Revoke.
    #
    # Example usage:
    #   class MyTokenAuth < HaveAPI::Authentication::Token::Provider
    #     protected
    #     def save_token(user, token, validity)
    #       user.tokens << ::Token.new(token: token, validity: validity)
    #     end
    #
    #     def revoke_token(user, token)
    #       user.tokens.delete(token: token)
    #     end
    #
    #     def find_user_by_credentials(username, password)
    #       ::User.find_by(login: username, password: password)
    #     end
    #
    #     def find_user_by_token(token)
    #       t = ::Token.find_by(token: token)
    #       t && t.user
    #     end
    #   end
    #
    # Finally put the provider in the authentication chain:
    #   api = HaveAPI.new(...)
    #   ...
    #   api.auth_chain << MyTokenAuth
    class Provider < Base
      def setup
        Resources::Token.token_instance ||= {}
        Resources::Token.token_instance[@version] = self
      end

      def authenticate(request)
        token = nil
        token ||= request[query_parameter]
        token ||= request.env[header_to_env]

        token && find_user_by_token(token)
      end

      def describe
        {
            http_header: http_header,
            query_parameter: query_parameter,
        }
      end

      protected
      # HTTP header that is searched for token.
      def http_header
        'X-HaveAPI-Auth-Token'
      end

      # Query parameter searched for token.
      def query_parameter
        :auth_token
      end

      # Generate token. Implicit implementation returns token of 100 chars.
      def generate_token
        SecureRandom.hex(50)
      end

      # Save generated +token+ for +user+. Token has given +validity+ period.
      # Returns a Time object which is token expiration.
      # Must be implemented.
      def save_token(user, token, validity)

      end

      # Revoke existing +token+ for +user+.
      # Must be implemented.
      def revoke_token(user, token)

      end

      # Used by action Resources::Token::Request when the user is requesting
      # a token. This method returns user object or nil.
      # Must be implemented.
      def find_user_by_credentials(username, password)

      end

      # Authenticate user by +token+. Return user object or nil.
      # Must be implemented.
      def find_user_by_token(token)

      end

      private
      def header_to_env
        "HTTP_#{http_header.upcase.gsub(/\-/, '_')}"
      end
    end
  end
end
