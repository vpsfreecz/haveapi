module HaveAPI
  class Context
    attr_accessor :server, :version, :request, :resource, :action, :path, :args,
                  :params, :current_user, :authorization, :endpoint, :resource_path,
                  :action_instance, :action_prepare, :layout

    def initialize(server, version: nil, request: nil, resource: [], action: nil,
                   path: nil, args: nil, params: nil, user: nil,
                   authorization: nil, endpoint: nil, resource_path: [])
      @server = server
      @version = version
      @request = request
      @resource = resource
      @action = action
      @path = path
      @args = args
      @params = params
      @current_user = user
      @authorization = authorization
      @endpoint = endpoint
      @resource_path = resource_path
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

      path.scan(/\{([a-zA-Z\-_]+)\}/) do |match|
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
      path.sub!(/\{[a-zA-Z\-_]+\}/, arg.to_s)
    end
  end
end
