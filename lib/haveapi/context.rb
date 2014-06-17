module HaveAPI
  class Context
    attr_accessor :server, :version, :resource, :action, :url, :args,
                  :params, :current_user, :authorization, :endpoint,
                  :action_instance, :action_prepare, :layout

    def initialize(server, version: nil, resource: [], action: nil,
                  url: nil, args: nil, params: nil, user: nil,
                  authorization: nil, endpoint: nil)
      @server = server
      @version = version
      @resource = resource
      @action = action
      @url = url
      @args = args
      @params = params
      @current_user = user
      @authorization = authorization
      @endpoint = endpoint
    end

    def resolved_url
      return @url unless @args

      ret = @url.dup

      @args.each do |arg|
        resolve_arg!(ret, arg)
      end

      ret
    end

    def url_for(action, args=nil)
      top_module = Kernel
      top_route = @server.routes[@version]

      action.to_s.split('::').each do |name|
        top_module = top_module.const_get(name)

        begin
          top_module.obj_type

        rescue NoMethodError
          next
        end

        if top_module.obj_type == :resource
          top_route = top_route[:resources][top_module]
        else
          top_route = top_route[:actions][top_module]
        end
      end

      ret = top_route.dup

      args.each { |arg| resolve_arg!(ret, arg) } if args

      ret
    end

    private
    def resolve_arg!(url, arg)
      url.sub!(/:[a-zA-Z\-_]+/, arg.to_s)
    end
  end
end
