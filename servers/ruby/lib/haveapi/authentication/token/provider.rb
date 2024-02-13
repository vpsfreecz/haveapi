require 'haveapi/authentication/base'
require 'haveapi/resource'
require 'haveapi/action'

module HaveAPI::Authentication
  module Token
    # Exception that has to be raised when generated token already exists.
    # Provider will catch it and generate another token.
    class TokenExists < Exception
    end

    # Provider for token authentication.
    #
    # This provider has to be configured using
    # {HaveAPI::Authentication::Token::Config}.
    #
    # Token auth contains API resource `token`. User can request a token by
    # calling action `Request`. The returned token is then used for
    # authenticating the user. Client sends the token with each request in
    # configured {HaveAPI::Authentication::Token::Config#http_header} or
    # {HaveAPI::Authentication::Token::Config#query_parameter}.
    #
    # Token can be revoked by calling action `Revoke` and renewed with `Renew`.
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
    # Authentication provider configuration:
    #   class MyTokenAuthConfig < HaveAPI::Authentication::Token::Config
    #     request do
    #       handle do |req, res|
    #         user = ::User.find_by(login: input[:user], password: input[:password])
    #
    #         if user.nil?
    #           res.error = 'invalid user or password'
    #           next res
    #         end
    #
    #         token = SecureRandom.hex(50)
    #         valid_to =
    #           if req.input[:lifetime] == 'permanent'
    #             nil
    #           else
    #             Time.now + req.input[:interval]
    #
    #         user.tokens << ::Token.new(
    #           token: token,
    #           lifetime: req.input[:lifetime],
    #           valid_to: valid_to,
    #           interval: req.input[:interval],
    #           label: req.request.user_agent,
    #         )
    #
    #         res.token = token
    #         res.valid_to = valid_to
    #         res.complete = true
    #         res.ok
    #       end
    #     end
    #
    #     renew do
    #       handle do |req, res|
    #         t = ::Token.find_by(user: req.user, token: req.token)
    #
    #         if t && t.lifetime.start_with('renewable')
    #           t.renew
    #           t.save
    #           res.valid_to = t.valid_to
    #           res.ok
    #         else
    #           res.error = 'unable to renew token'
    #           res
    #         end
    #       end
    #     end
    #
    #     revoke do
    #       handle do |req, res|
    #         req.user.tokens.delete(token: req.token)
    #         res.ok
    #       end
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
    #   api.auth_chain << HaveAPI::Authentication::Token.with_config(MyTokenAuthConfig)
    class Provider < Base
      auth_method :token

      # Configure the token provider
      # @param cfg [Config]
      def self.with_config(cfg)
        Module.new do
          define_singleton_method(:new) do |*args|
            Provider.new(*args, cfg)
          end
        end
      end

      attr_reader :config

      def initialize(server, v, cfg)
        @config = cfg.new(server, v)
        super(server, v)
      end

      def setup
        @server.allow_header(config.class.http_header)
      end

      def resource_module
        return @module if @module

        provider = self

        @module = Module.new do
          const_set(:Token, provider.send(:token_resource))
        end
      end

      # Authenticate request
      # @param request [Sinatra::Request]
      def authenticate(request)
        t = token(request)

        t && config.find_user_by_token(request, t)
      end

      # Extract token from HTTP request
      # @param request [Sinatra::Request]
      # @return [String]
      def token(request)
        request[config.class.query_parameter] || request.env[header_to_env]
      end

      def describe
        {
          http_header: config.class.http_header,
          query_parameter: config.class.query_parameter,
          description: 'The client authenticates with credentials, usually username and password, and gets a token. From this point, the credentials can be forgotten and the token is used instead. Tokens can have different lifetimes, can be renewed and revoked. The token is passed either via HTTP header or query parameter.'
        }
      end

      private

      def header_to_env
        "HTTP_#{config.class.http_header.upcase.gsub('-', '_')}"
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
              if (block = provider.config.class.request.input)
                instance_exec(&block)
              end

              string :lifetime, label: 'Lifetime', required: true,
                                choices: %i[fixed renewable_manual renewable_auto permanent],
                                desc: <<~END
                                  fixed - the token has a fixed validity period, it cannot be renewed
                                  renewable_manual - the token can be renewed, but it must be done manually via renew action
                                  renewable_auto - the token is renewed automatically to now+interval every time it is used
                                  permanent - the token will be valid forever, unless deleted
                                END
              integer :interval, label: 'Interval',
                                 desc: 'How long will requested token be valid, in seconds.',
                                 default: 60 * 5, fill: true
            end

            output(:hash) do
              string :token
              datetime :valid_to
              bool :complete
              string :next_action
            end

            authorize do
              allow
            end

            def exec
              config = self.class.resource.token_instance.config

              begin
                result = config.class.request.handle.call(ActionRequest.new(
                                                            request:,
                                                            input:
                                                          ), ActionResult.new)
              rescue HaveAPI::AuthenticationError => e
                error(e.message)
              end

              unless result.ok?
                error(result.error || 'invalid authentication credentials')
              end

              {
                token: result.token,
                valid_to: result.valid_to,
                complete: result.complete?,
                next_action: result.next_action
              }
            end
          end

          define_action(:Revoke) do
            http_method :post
            auth true

            authorize do
              allow
            end

            def exec
              provider = self.class.resource.token_instance
              result = provider.config.class.revoke.handle.call(ActionRequest.new(
                                                                  request:,
                                                                  user: current_user,
                                                                  token: provider.token(request)
                                                                ), ActionResult.new)

              if result.ok?
                ok
              else
                error(result.error || 'revoke failed')
              end
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
              provider = self.class.resource.token_instance
              result = provider.config.renew_token(ActionRequest.new(
                                                     request:,
                                                     user: current_user,
                                                     token: provider.token(request)
                                                   ), ActionResult.new)

              if result.ok?
                { valid_to: result.valid_to }
              else
                error(result.error || 'renew failed')
              end
            end
          end

          provider.config.class.actions.each do |name, config|
            define_action(:"#{name.to_s.capitalize}") do
              http_method :post
              auth false

              input(:hash) do
                string :token, required: true
                instance_exec(&config.input) if config.input
              end

              output(:hash) do
                string :token
                datetime :valid_to
                bool :complete
                string :next_action
              end

              authorize do
                allow
              end

              define_method(:exec) do
                begin
                  result = config.handle.call(ActionRequest.new(
                                                request:,
                                                input:,
                                                token: input[:token]
                                              ), ActionResult.new)
                rescue HaveAPI::AuthenticationError => e
                  error(e.message)
                end

                unless result.ok?
                  error(result.error || 'authentication failed')
                end

                {
                  token: result.token,
                  valid_to: result.valid_to,
                  complete: result.complete?,
                  next_action: result.next_action
                }
              end
            end
          end
        end
      end
    end
  end
end
