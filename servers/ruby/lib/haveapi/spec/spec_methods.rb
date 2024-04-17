module HaveAPI::Spec
  # Helper methods for specs.
  module SpecMethods
    include Rack::Test::Methods

    def app
      return @api.app if @api

      auth = get_opt(:auth_chain)
      default = get_opt(:default_version)

      @api = HaveAPI::Server.new(get_opt(:api_module))
      @api.auth_chain << auth if auth
      @api.use_version(get_opt(:versions) || :all)
      @api.default_version = default if default
      @api.mount(get_opt(:mount) || '/')
      @api.app
    end

    # Login with HTTP basic auth.
    def login(*credentials)
      basic_authorize(*credentials)
    end

    # Make API request.
    # This method is a wrapper for Rack::Test::Methods. Input parameters
    # are encoded into JSON and sent with a correct Content-Type.
    # Two modes:
    #   http_method, path, params = {}
    #   [resource], action, params, &block
    def call_api(*args, &)
      if args[0].is_a?(::Array) || args[1].is_a?(::Symbol)
        r_name, a_name, params = args

        app

        action, path = find_action(
          (params && params[:version]) || @api.default_version,
          r_name, a_name
        )

        method(action.http_method).call(
          path,
          params && params.to_json,
          { 'Content-Type' => 'application/json' }
        )

      else
        http_method, path, params = args

        method(http_method).call(
          path,
          params && params.to_json,
          { 'Content-Type' => 'application/json' }
        )
      end
    end

    # Mock action call. Note that this method does not involve rack request/response
    # in any way. It simply creates an instance of specified action and executes it.
    # Provided block is executed in the context of the action instance after `exec()`
    # has been called.
    #
    # If `exec()` signals error, the block is not called at all, but `RuntimeError`
    # is raised instead.
    #
    # Authentication does not take place. Argument `user` may be used to provide
    # user object. That will signify that the user is authenticated and it will be passed
    # to Action.authorize.
    #
    # @param r_name [Array, Symbol] path to resource in the API
    # @param a_name [Symbol] name of wanted action
    # @param params [Hash] a hash of parameters, must contain correct namespace
    # @param version [any] API version, if not specified, the default version is used
    # @param user [any] object representing authenticated user
    # @yield [self] the block is executed in the action instance
    def mock_action(r_name, a_name, params, version: nil, user: nil, &)
      app
      v = version || @api.default_version
      action, path = find_action(v, r_name, a_name)
      m = MockAction.new(self, @api, action, path, v)
      m.call(params, user:, &)
    end

    # Return parsed API response.
    # @return [HaveAPI::Spec::ApiResponse]
    def api_response
      if last_response == @last_response
        @api_response ||= ApiResponse.new(last_response.body)
      else
        @last_response = last_response
        @api_response = ApiResponse.new(last_response.body)

      end
    end

    protected

    def get_opt(name)
      self.class.opts && self.class.opts[name]
    end

    def find_action(v, r_name, a_name)
      # Make sure the API is built
      app

      resources = r_name.is_a?(::Array) ? r_name : [r_name]

      top = @api.routes[v]

      resources.each do |r|
        top = top[:resources].detect do |k, _|
          k.resource_name.to_sym == r
        end.second
      end

      top[:actions].detect do |k, _v|
        k.to_s.demodulize.underscore.to_sym == a_name
      end
    end
  end
end
