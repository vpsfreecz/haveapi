require 'haveapi/authentication/base'
require 'haveapi/resource'
require 'haveapi/action'

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
    #     def revoke_token(request, user, token)
    #       user.tokens.delete(token: token)
    #     end
    #
    #     def renew_token(request, user, token)
    #       t = ::Token.find_by(user: user, token: token)
    #
    #       if t.lifetime.start_with('renewable')
    #         t.renew
    #         t.save
    #         t.valid_to
    #       end
    #     end
    #
    #     def find_user_by_credentials(request, username, password)
    #       ::User.find_by(login: username, password: password)
    #     end
    #
    #     def find_user_by_token(request, token)
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
      class << self
        def request_input(&block)
          if block.nil?
            @request_input || Proc.new do
              string :login, label: 'User', required: true
              password :password, label: 'Password', required: true
            end
          else
            @request_input = block
          end
        end
      end

      def setup
        @server.allow_header(http_header)
      end

      def resource_module
        return @module if @module
        provider = self

        @module = Module.new do
          const_set(:Token, provider.send(:token_resource))
        end
      end

      # @param params [HaveAPI::Params]
      def request_input(params)
        params.instance_exec(&self.class.request_input)
      end

      # Authenticate request
      # @param request [Sinatra::Request]
      def authenticate(request)
        t = token(request)

        t && find_user_by_token(request, t)
      end

      # Extract token from HTTP request
      # @param request [Sinatra::Request]
      # @return [String]
      def token(request)
        request[query_parameter] || request.env[header_to_env]
      end

      def describe
        {
            http_header: http_header,
            query_parameter: query_parameter,
            description: "The client authenticates with username and password and gets "+
                         "a token. From this point, the password can be forgotten and "+
                         "the token is used instead. Tokens can have different lifetimes, "+
                         "can be renewed and revoked. The token is passed either via HTTP "+
                         "header or query parameter."
        }
      end

      protected
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

      # Save generated +token+ for +user+. Token has given +lifetime+
      # and when not permanent, also a +interval+ of validity.
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

      # Revoke existing +token+ for +user+.
      # Must be implemented.
      # @param request [Sinatra::Request]
      # @param user [Object]
      # @param token [String]
      def revoke_token(request, user, token)

      end

      # Renew existing +token+ for +user+.
      # Returns a date time which is token expiration.
      # Must be implemented.
      # @param request [Sinatra::Request]
      # @param user [Object]
      # @param token [String]
      def renew_token(request, user, token)

      end

      # Used by action Resources::Token::Request when the user is requesting
      # a token. This method returns user object or nil.
      # Must be implemented.
      # @param request [Sinatra::Request]
      # @param input [Hash]
      # @return [Object]
      def find_user_by_credentials(request, input)

      end

      # Authenticate user by +token+. Return user object or nil.
      # If the token was created as auto-renewable, this method
      # is responsible for its renewal.
      # Must be implemented.
      # @param request [Sinatra::Request]
      # @param token [String]
      # @return [Object]
      def find_user_by_token(request, token)

      end

      private
      def header_to_env
        "HTTP_#{http_header.upcase.gsub(/\-/, '_')}"
      end

      def token_resource
        provider = self

        HaveAPI::Resource.define_resource(:Token) do
          define_singleton_method(:token_instance) { provider }

          auth false
          version :all

          define_action(:Request) do
            route ''
            http_method :post

            input(:hash) do
              provider.request_input(self)
              string :lifetime, label: 'Lifetime', required: true,
                      choices: %i(fixed renewable_manual renewable_auto permanent),
                      desc: <<END
fixed - the token has a fixed validity period, it cannot be renewed
renewable_manual - the token can be renewed, but it must be done manually via renew action
renewable_auto - the token is renewed automatically to now+interval every time it is used
permanent - the token will be valid forever, unless deleted
END
              integer :interval, label: 'Interval',
                      desc: 'How long will requested token be valid, in seconds.',
                      default: 60*5, fill: true
            end

            output(:hash) do
              string :token
              datetime :valid_to
            end

            authorize do
              allow
            end

            def exec
              klass = self.class.resource.token_instance

              begin
                user = klass.send(
                  :find_user_by_credentials,
                  request,
                  input[:login],
                  input[:password]
                )
              rescue HaveAPI::AuthenticationError => e
                error(e.message)
              end

              error('bad login or password') unless user

              token = expiration = nil

              loop do
                begin
                  token = klass.send(:generate_token)
                  expiration = klass.send(
                    :save_token,
                    @request,
                    user,
                    token,
                    input[:lifetime],
                    input[:interval]
                  )
                  break

                rescue TokenExists
                  next
                end
              end

              {token: token, valid_to: expiration}
            end
          end

          define_action(:Revoke) do
            http_method :post
            auth true

            authorize do
              allow
            end

            def exec
              klass = self.class.resource.token_instance
              klass.send(
                :revoke_token,
                request,
                current_user,
                klass.token(request)
              )
            end
          end

          define_action(:Renew) do
            http_method :post
            auth true

            output(:hash) do
              datetime :valid_to
            end

            authorize do
              allow
            end

            def exec
              klass = self.class.resource.token_instance
              {
                valid_to: klass.send(
                  :renew_token,
                  request,
                  current_user,
                  klass.token(request)
                ),
              }
            end
          end
        end
      end
    end
  end
end
