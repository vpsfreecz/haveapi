module HaveAPI::Authentication
  module Token
    # Configuration for {HaveAPI::Authentication::Token::Provider}
    #
    # Create a subclass and use with {HaveAPI::Authentication::Token#with_config}.
    class Config
      class << self
        # Configure token request input parameters for user credentials
        #
        # The given block is executed in the context of {HaveAPI::Params}.
        # The default parameters are `login` and `password`.
        def request_input(&block)
          if block
            @request_input = block
          else
            @request_input
          end
        end
      end

      def initialize(server, v)
        @server = server
        @version = v
      end

      # HTTP header that is searched for token.
      # @return [String]
      def http_header
        'X-HaveAPI-Auth-Token'
      end

      # Query parameter searched for token.
      # @return [Symbol]
      def query_parameter
        :_auth_token
      end

      # Generate token. Implicit implementation returns token of 100 chars.
      # @param [String]
      def generate_token
        SecureRandom.hex(50)
      end

      # Save generated `token` for `user`. Token has given `lifetime`
      # and when not permanent, also a `interval` of validity.
      # Returns a date time which is token expiration.
      # It is up to the implementation of this method to remember
      # token lifetime and interval.
      # Must be implemented.
      # @param request [Sinatra::Request]
      # @param user [Object]
      # @param token [String]
      # @param lifetime [String]
      # @param interval [Integer]
      def save_token(request, user, token, lifetime, interval)

      end

      # Revoke existing `token` for `user`.
      # Must be implemented.
      # @param request [Sinatra::Request]
      # @param user [Object]
      # @param token [String]
      def revoke_token(request, user, token)

      end

      # Renew existing `token` for `user`.
      #
      # Returns a date time which is token expiration.
      # Must be implemented.
      # @param request [Sinatra::Request]
      # @param user [Object]
      # @param token [String]
      # @return [Time] token expiration
      def renew_token(request, user, token)

      end

      # Used when the user is requesting a token.
      #
      # This method returns user object or nil.
      # Must be implemented.
      # @param request [Sinatra::Request]
      # @param input [Hash]
      # @return [Object, nil]
      # @raise [HaveAPI::AuthenticationError]
      def find_user_by_credentials(request, input)

      end

      # Authenticate user by `token`.
      #
      # Return user object or nil.
      # If the token was created as auto-renewable, this method
      # is responsible for its renewal.
      # Must be implemented.
      # @param request [Sinatra::Request]
      # @param token [String]
      # @return [Object, nil]
      def find_user_by_token(request, token)

      end
    end
  end
end
