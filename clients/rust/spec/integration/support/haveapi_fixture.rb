# frozen_string_literal: true

require_relative '../../../../../servers/ruby/test_support/client_test_api'

# The generic fixture's OPTIONS profile deliberately includes its secured
# actions. This changes test description visibility only; HTTP authentication
# and action authorization still use the original server implementation.
HaveAPI::ClientTestAPI::DocFilter.module_eval { remove_method :describe }

module RustClientFixtures
  # These are test-only additions to the real HaveAPI server's shared client
  # fixture. None of these actions are added to the public vpsAdmin snapshot.
  module Haveapi
    module_function

    def extend_token_config!(documentation_examples: false)
      config = HaveAPI::ClientTestAPI::TokenConfig
      original_request = config.request.handle
      config.request do
        handle do |req, res|
          if documentation_examples
            if req.input[:user] == 'user' && req.input[:password] == 'secret'
              token = 'example-token'
              config.tokens[token] = HaveAPI::ClientTestAPI::USERS.fetch('user')
              res.token = token
              res.valid_to = Time.now + 3600
              res.complete = true
              res.ok
            else
              res.error = 'invalid credentials'
            end
            next res
          end
          step = { 'totp' => :totp, 'reset' => :reset_password, 'unknown' => :future_step }[req.input[:password]]
          next original_request.call(req, res) unless req.input[:user] == 'user' && step

          res.complete = false
          res.token = "pending-#{step}"
          res.next_action = step
          res.valid_to = Time.now + 300
          res.ok
        end
      end

      config.action :totp do
        input { string :code, required: true }
        handle do |req, res|
          unless req.input[:token] == 'pending-totp' && req.input[:code] == '123456'
            res.error = 'invalid totp code'
            next res
          end

          res.complete = false
          res.token = 'pending-reset_password'
          res.next_action = :reset_password
          res.ok
        end
      end

      config.action :reset_password do
        input do
          password :new_password1, required: true
          password :new_password2, required: true
        end
        handle do |req, res|
          unless req.input[:token] == 'pending-reset_password' &&
                 req.input[:new_password1] == req.input[:new_password2]
            res.error = 'invalid reset or passwords do not match'
            next res
          end

          token = 'token-user'
          HaveAPI::ClientTestAPI::TokenConfig.tokens[token] = HaveAPI::ClientTestAPI::USERS.fetch('user')
          res.complete = true
          res.token = token
          res.ok
        end
      end
    end

    class OAuthConfig < HaveAPI::Authentication::OAuth2::Config
      def base_url
        'http://127.0.0.1'
      end

      def find_user_by_access_token(_request, token)
        HaveAPI::ClientTestAPI::USERS.fetch('user') if token == 'oauth-user'
      end
    end

    OAuthProvider = HaveAPI::Authentication::OAuth2.with_config(OAuthConfig)

    class DocumentationBasicProvider < HaveAPI::Authentication::Basic::Provider
      protected

      def find_user(_request, username, password)
        HaveAPI::ClientTestAPI::USERS.fetch('user') if username == 'user' && password == 'secret'
      end
    end

    class DocumentationOAuthConfig < OAuthConfig
      def find_user_by_access_token(_request, token)
        HaveAPI::ClientTestAPI::USERS.fetch('user') if token == 'example-access-token'
      end
    end

    DocumentationOAuthProvider = HaveAPI::Authentication::OAuth2.with_config(DocumentationOAuthConfig)

    def extend_resources!
      HaveAPI::ClientTestAPI::Resources.define_resource(:RustFixture) do
        auth false

        # Query null and body null share the same declared input but use the
        # real server's separate query/JSON parsers and validation pipeline.
        { Echo: :post, Query: :get, Unnamespaced: :post }.each do |name, method|
          define_action(name) do
            http_method method
            authorize { allow }
            input(:hash, namespace: name == :Unnamespaced ? false : :rust_fixture) do
              integer :number, nullable: true
              bool :flag, nullable: true
              string :text
            end
            output(:hash) do
              custom :received
            end

            define_method(:exec) { { received: input } }
          end
        end

        define_action(:DeleteBody) do
          http_method :delete
          authorize { allow }
          input(:hash) do
            integer :number, nullable: true
            integer :zero
            bool :flag
            string :text
            string :omitted
            custom :value
          end
          meta(:global) do
            input { custom :global_marker }
          end
          meta(:object) do
            input { custom :object_marker }
          end
          output(:hash) do
            custom :received
            custom :received_meta
          end
          def exec
            { received: input, received_meta: meta }
          end
        end

        # Custom is a top-level HaveAPI type constant. The resource DSL skips
        # inherited constant names, so give this action a distinct name.
        define_action(:EchoCustom) do
          http_method :post
          authorize { allow }
          input(:hash) { custom :value, required: true }
          output(:hash) { custom :value }
          def exec
            input
          end
        end

        define_action(:CustomQuery) do
          http_method :get
          authorize { allow }
          input(:hash) { custom :value, required: true }
          output(:hash) { custom :value }
          def exec
            input
          end
        end

        define_action(:Batch) do
          http_method :post
          authorize { allow }
          input(:hash_list) { integer :number, required: true }
          output(:hash_list) { integer :number }
          def exec
            input
          end
        end

        define_action(:Association) do
          http_method :get
          authorize { allow }
          output(:hash) do
            resource HaveAPI::ClientTestAPI::Resources::Project, value_label: :name
          end
          def exec
            { project: { id: 1, name: 'Alpha' } }
          end
        end
      end
    end

    def build(mount: '/', documentation_examples: false)
      extend_token_config!(documentation_examples:)
      extend_resources!
      HaveAPI.implicit_version = '1.0'
      HaveAPI::ClientTestAPI.reset!
      api = HaveAPI::Server.new(HaveAPI::ClientTestAPI::Resources)
      api.use_version(:all)
      api.default_version = '1.0'
      api.auth_chain << (documentation_examples ? DocumentationBasicProvider : HaveAPI::ClientTestAPI::BasicProvider)
      api.auth_chain << HaveAPI::ClientTestAPI::TokenProvider
      api.auth_chain << (documentation_examples ? DocumentationOAuthProvider : OAuthProvider)
      api.action_state = HaveAPI::ClientTestAPI::ActionStateBackend
      api.mount(mount)
      api.app
    end
  end
end
