module HaveAPI
  class Context
    attr_accessor :server, :version, :request, :resource, :action, :path, :args,
                  :params, :current_user, :authorization, :endpoint, :resource_path,
                  :path_params, :input, :action_instance, :action_prepare, :layout, :doc,
                  :auth_users_by_version

    def initialize(server, version: nil, request: nil, resource: [], action: nil,
                   path: nil, args: nil, params: nil, user: nil,
                   authorization: nil, endpoint: nil, resource_path: [], doc: false,
                   auth_users_by_version: nil, path_params: nil, input: nil)
      @server = server
      @version = version
      @request = request
      @resource = resource
      @action = action
      @path = path
      @args = args
      @params = params
      @path_params = path_params
      @input = input
      @current_user = user
      @authorization = authorization
      @endpoint = endpoint
      @resource_path = resource_path
      @doc = doc
      @auth_users_by_version = auth_users_by_version
    end

    def resolved_path
      return @path unless @args

      ret = @path.dup

      @args.each do |arg|
        resolve_arg!(ret, arg)
      end

      ret
    end

    def path_for(action, args = nil)
      top_module = Kernel
      top_route = @server.routes[@version]

      action.to_s.split('::').each do |name|
        top_module = top_module.const_get(name)

        begin
          top_module.obj_type
        rescue NoMethodError
          next
        end

        top_route = if top_module.obj_type == :resource
                      top_route[:resources][top_module]
                    else
                      top_route[:actions][top_module]
                    end
      end

      ret = top_route.dup

      args.each { |arg| resolve_arg!(ret, arg) } if args

      ret
    end

    def action_path_for(action, args = nil)
      ret = @server.path_for_action(@version, action) || path_for(action)

      ret = ret.dup
      args.each { |arg| resolve_arg!(ret, arg) } if args

      ret
    end

    def path_params_for(action, args)
      action.path_params(action_path_for(action), args)
    end

    def call_path_params(action, obj)
      ret = params && action.resolve_path_params(obj)

      return [ret] if ret && !ret.is_a?(Array)

      ret
    end

    def path_with_params(action, obj)
      path_for(action, call_path_params(action, obj))
    end

    def path_params_from_args
      ret = {}
      return ret if args.nil?

      my_args = args.clone

      path.scan(/\{([a-zA-Z0-9\-_]+)\}/) do |match|
        path_param = match.first
        ret[path_param] = my_args.shift
      end

      ret
    end

    def action_scope
      "#{resource_path.map(&:downcase).join('.')}##{action.action_name.underscore}"
    end

    private

    def resolve_arg!(path, arg)
      value = arg.to_s
      raise HaveAPI::ValidationError, 'invalid path parameter encoding' unless value.valid_encoding?

      path.sub!(/\{[a-zA-Z0-9\-_]+\}/, value)
    end
  end
end
