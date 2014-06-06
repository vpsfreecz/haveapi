module HaveAPI
  class Context
    attr_accessor :server, :version, :resource, :action, :url, :current_user, :authorization

    def initialize(server, version: nil, resource: [], action: nil, url: nil, user: nil, authorization: nil)
      @server = server
      @version = version
      @resource = resource
      @action = action
      @url = url
      @current_user = user
      @authorization = authorization
    end

    def url_for(action)
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
          top_route = top_route[:resources] ? top_route[:resources][top_module] : top_route[top_module]
        else
          top_route = top_route[:actions][top_module]
        end
      end

      top_route
    end
  end
end
