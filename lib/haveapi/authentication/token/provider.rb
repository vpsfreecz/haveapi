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
    # === \Example usage:
    #
    # \Token model:
    #   class ApiToken < ActiveRecord::Base
    #     belongs_to :user
    #
    #     validates :user_id, :token, presence: true
    #     validates :token, length: {is: 100}
    #
    #     enum lifetime: %i(fixed renewable_manual renewable_auto permanent)
    #
    #     def renew
    #       self.valid_to = Time.now + interval
    #     end
    #   end
    #
    # Authentication provider:
    #   class MyTokenAuth < HaveAPI::Authentication::Token::Provider
    #     protected
    #     def save_token(request, user, token, lifetime, interval)
    #       user.tokens << ::Token.new(token: token, lifetime: lifetime,
    #                                  valid_to: (lifetime != 'permanent' ? Time.now + interval : nil),
    #                                  interval: interval, label: request.user_agent)
    #     end
    #
    #     def revoke_token(user, token)
    #       user.tokens.delete(token: token)
    #     end
    #
    #     def renew_token(user, token)
    #       t = ::Token.find_by(user: user, token: token)
    #
    #       if t.lifetime.start_with('renewable')
    #         t.renew
    #         t.save
    #         t.valid_to
    #       end
    #     end
    #
    #     def find_user_by_credentials(username, password)
    #       ::User.find_by(login: username, password: password)
    #     end
    #
    #     def find_user_by_token(token)
    #       t = ::Token.find_by(token: token)
    #
    #       if t
    #         # Renew the token if needed
    #         if t.lifetime == 'renewable_auto'
    #           t.renew
    #           t.save
    #         end
    #
    #         t.user # return the user
    #       end
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

        @server.allow_header(http_header)
      end

      def authenticate(request)
        t = token(request)

        t && find_user_by_token(t)
      end

      def token(request)
        request[query_parameter] || request.env[header_to_env]
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
        :_auth_token
      end

      # Generate token. Implicit implementation returns token of 100 chars.
      def generate_token
        SecureRandom.hex(50)
      end

      # Save generated +token+ for +user+. Token has given +lifetime+
      # and when not permanent, also a +interval+ of validity.
      # Returns a date time which is token expiration.
      # It is up to the implementation of this method to remember
      # token lifetime and interval.
      # Must be implemented.
      def save_token(request, user, token, lifetime, interval)

      end

      # Revoke existing +token+ for +user+.
      # Must be implemented.
      def revoke_token(user, token)

      end

      # Renew existing +token+ for +user+.
      # Returns a date time which is token expiration.
      # Must be implemented.
      def renew_token(user, token)

      end

      # Used by action Resources::Token::Request when the user is requesting
      # a token. This method returns user object or nil.
      # Must be implemented.
      def find_user_by_credentials(username, password)

      end

      # Authenticate user by +token+. Return user object or nil.
      # If the token was created as auto-renewable, this method
      # is responsible for its renewal.
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
