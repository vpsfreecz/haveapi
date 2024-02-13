module HaveAPI::Authentication
  module Token
    # Configuration for {HaveAPI::Authentication::Token::Provider}
    #
    # Create a subclass and use with {HaveAPI::Authentication::Token#with_config}.
    class Config
      class << self
        # Configure token request action
        def request(&block)
          if block
            if @request
              @request.update(block)
            else
              @request = ActionConfig.new(block)
            end
          else
            @request
          end
        end

        %i[renew revoke].each do |name|
          # Configuration method
          define_method(name) do |&block|
            var = :"@#{name}"
            val = instance_variable_get(var)

            if block
              if val
                val.update(block)
              else
                instance_variable_set(var, ActionConfig.new(block, input: false))
              end
            else
              val
            end
          end
        end

        # @param name [Symbol]
        def action(name, &block)
          @actions ||= {}
          @actions[name] = ActionConfig.new(block)
        end

        # @return [Hash]
        def actions
          @actions || {}
        end

        # HTTP header that is searched for token
        # @param header [String, nil]
        # @return [String]
        def http_header(header = nil)
          if header
            @http_header = header
          else
            @http_header || 'X-HaveAPI-Auth-Token'
          end
        end

        # Query parameter searched for token
        # @param param [Symbol]
        # @return [Symbol]
        def query_parameter(param = nil)
          if param
            @query_param = param
          else
            @query_param || :_auth_token
          end
        end

        def inherited(subclass)
          # Default request
          subclass.request do
            input do
              string :user, label: 'User', required: true
              password :password, label: 'Password', required: true
              string :scope, label: 'Scope', default: 'all', fill: true
            end

            handle do
              raise NotImplementedError
            end
          end

          # Default renew and revoke
          %i[renew revoke].each do |name|
            subclass.send(name) do
              handle do
                raise NotImplementedError
              end
            end
          end
        end
      end

      def initialize(server, v)
        @server = server
        @version = v
      end

      # Authenticate request by `token`
      #
      # Return user object or nil.
      # If the token was created as auto-renewable, this method
      # is responsible for its renewal.
      # Must be implemented.
      # @param request [Sinatra::Request]
      # @param token [String]
      # @return [Object, nil]
      def find_user_by_token(request, token); end
    end
  end
end
