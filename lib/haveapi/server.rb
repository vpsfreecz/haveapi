module HaveAPI
  class Server
    attr_reader :root, :routes, :module_name, :auth_chain, :versions, :default_version

    module ServerHelpers
      def authenticate!(v)
        require_auth! unless authenticated?(v)
      end

      def authenticated?(v)
        return @current_user if @current_user

        @current_user = settings.api_server.send(:do_authenticate, v, request)
        settings.api_server.send(:invoke_hook, :post_authenticated, @current_user)
        @current_user
      end

      def current_user
        @current_user
      end

      def pretty_format(obj)
        ret = ''
        PP.pp(obj, ret)
      end

      def require_auth!
        report_error(401, {'WWW-Authenticate' => 'Basic realm="Restricted Area"'},
                     'Action requires user to authenticate')
      end

      def report_error(code, headers, msg)
        @halted = true
        content_type @formatter.content_type, charset: 'utf-8'
        halt code, headers, @formatter.format(false, nil, msg)
      end

      def root
        settings.api_server.root
      end

      def logout_url
        ret = url("#{root}_logout")
        ret.insert(ret.index('//') + 2, '_log:out@')
      end

      def doc(file)
        markdown :"../../../doc/#{file}"
      end
    end

    def initialize(module_name = HaveAPI.module_name)
      @module_name = module_name
      @auth_chain = HaveAPI::Authentication::Chain.new(self)
      @hooks = {post_authenticated: []}
    end

    # Include specific version +v+ of API.
    # +v+ can be one of:
    # [:all]     use all available versions
    # [Array]    use all versions in +Array+
    # [version]  include only concrete version
    # +default+ is set only when including concrete version. Use
    # set_default_version otherwise.
    def use_version(v, default: false)
      @versions ||= []

      if v == :all
        @versions = HaveAPI.get_versions(@module_name)
      elsif v.is_a?(Array)
        @versions += v
        @versions.uniq!
      else
        @versions << v
        @default_version = v if default
      end
    end

    # Set default version of API.
    def set_default_version(v)
      @default_version = v
    end

    # Load routes for all resource from included API versions.
    # All routes are mounted under prefix +path+.
    # If no default version is set, the last included version is used.
    def mount(prefix='/')
      @root = prefix

      @sinatra = Sinatra.new do
        set :views, settings.root + '/views'
        set :public_folder, settings.root + '/public'
        set :bind, '0.0.0.0'

        helpers ServerHelpers

        before do
          @formatter = OutputFormatter.new

          unless @formatter.supports?(request.accept)
            @halted = true
            halt 406, "Not Acceptable\n"
          end

          content_type @formatter.content_type, charset: 'utf-8'
        end

        not_found do
          report_error(404, {}, 'Action not found') unless @halted
        end

        after do
          ActiveRecord::Base.clear_active_connections!
        end
      end

      @sinatra.set(:api_server, self)

      @routes = {}
      @default_version ||= @versions.last

      # Mount root
      @sinatra.get @root do
        authenticated?(settings.api_server.default_version)

        @api = settings.api_server.describe(Context.new(settings.api_server, user: current_user,
                                            params: params))

        content_type 'text/html'
        erb :index, layout: :main_layout
      end

      @sinatra.options @root do
        authenticated?(settings.api_server.default_version)
        ret = nil

        case params[:describe]
          when 'versions'
            ret = {versions: settings.api_server.versions,
                   default: settings.api_server.default_version}

          when 'default'
            ret = settings.api_server.describe_version(Context.new(settings.api_server, version: settings.api_server.default_version,
                                                                  user: current_user, params: params))

          else
            ret = settings.api_server.describe(Context.new(settings.api_server, user: current_user,
                                                           params: params))
        end

        @formatter.format(true, ret)
      end

      # Doc
      @sinatra.get "#{@root}doc" do
        content_type 'text/html'
        erb :main_layout do
          GitHub::Markdown.render(File.new(settings.views + '/../../../README.md').read)
        end
      end

      @sinatra.get %r{#{@root}doc/([^\.]+)[\.md]?} do |f|
        content_type 'text/html'
        erb :doc_layout, layout: :main_layout do
          begin
            @content = doc(f)

          rescue Errno::ENOENT
            halt 404
          end

          @sidebar = erb :protocol_sidebar
        end
      end

      # Login/logout links
      @sinatra.get "#{root}_login" do
        if current_user
          redirect back
        else
          authenticate!(settings.api_server.default_version) # FIXME
        end
      end

      @sinatra.get "#{root}_logout" do
        require_auth!
      end

      @auth_chain << HaveAPI.default_authenticate if @auth_chain.empty?
      @auth_chain.setup(@versions)

      # Mount default version first
      mount_version(@root, @default_version)

      @versions.each do |v|
        mount_version(version_prefix(v), v)
      end
    end

    def mount_version(prefix, v)
      @routes[v] ||= {}
      @routes[v][:resources] = {}

      @sinatra.get prefix do
        authenticated?(v)

        @v = v
        @help = settings.api_server.describe_version(Context.new(settings.api_server, version: v,
                                                                 user: current_user, params: params))
        content_type 'text/html'
        erb :doc_layout, layout: :main_layout do
          @content = erb :version_page
          @sidebar = erb :version_sidebar
        end
      end

      @sinatra.options prefix do
        authenticated?(v)

        @formatter.format(true, settings.api_server.describe_version(Context.new(settings.api_server, version: v,
                                                                              user: current_user, params: params)))
      end

      HaveAPI.get_version_resources(@module_name, v).each do |resource|
        mount_resource(prefix, v, resource, @routes[v][:resources])
      end
    end

    def mount_resource(prefix, v, resource, hash)
      hash[resource] = {resources: {}, actions: {}}

      resource.routes(prefix).each do |route|
        if route.is_a?(Hash)
          hash[resource][:resources][route.keys.first] = mount_nested_resource(v, route.values.first)

        else
          hash[resource][:actions][route.action] = route.url
          mount_action(v, route)
        end
      end
    end

    def mount_nested_resource(v, routes)
      ret = {resources: {}, actions: {}}

      routes.each do |route|
        if route.is_a?(Hash)
          ret[:resources][route.keys.first] = mount_nested_resource(v, route.values.first)

        else
          ret[:actions][route.action] = route.url
          mount_action(v, route)
        end
      end

      ret
    end

    def mount_action(v, route)
      @sinatra.method(route.http_method).call(route.url) do
        authenticate!(v) if route.action.auth

        request.body.rewind

        begin
          body = request.body.read

          if body.empty?
            body = nil
          else
            body = JSON.parse(body, symbolize_names: true)
          end

        rescue => e
          report_error(400, {}, 'Bad JSON syntax')
        end

        action = route.action.new(request, v, params, body, Context.new(settings.api_server, version: v,
                                                                        action: route.action, url: route.url,
                                                                        params: params,
                                                                        user: current_user, endpoint: true))

        unless action.authorized?(current_user)
          report_error(403, {}, 'Access denied. Insufficient permissions.')
        end

        status, reply, errors = action.safe_exec

        @formatter.format(
            status,
            status  ? reply : nil,
            !status ? reply : nil,
            errors
        )
      end

      @sinatra.options route.url do |*args|
        route_method = route.http_method.to_s.upcase

        pass if params[:method] && params[:method] != route_method

        authenticate!(v) if route.action.auth

        begin
          desc = route.action.describe(Context.new(settings.api_server, version: v,
                                                   action: route.action, url: route.url,
                                                   args: args, params: params,
                                                   user: current_user, endpoint: true))

          unless desc
            report_error(403, {}, 'Access denied. Insufficient permissions.')
          end

        rescue ActiveRecord::RecordNotFound
          report_error(404, {}, 'Object not found')
        end

        @formatter.format(true, desc)
      end
    end

    def describe(context)
      context.version = @default_version

      ret = {
          default_version: @default_version,
          versions: {default: describe_version(context)},
      }

      @versions.each do |v|
        context.version = v
        ret[:versions][v] = describe_version(context)
      end

      ret
    end

    def describe_version(context)
      ret = {
          authentication: @auth_chain.describe(context),
          resources: {},
          help: version_prefix(context.version)
      }

      #puts JSON.pretty_generate(@routes)

      @routes[context.version][:resources].each do |resource, children|
        r_name = resource.to_s.demodulize.underscore
        r_desc = describe_resource(resource, children, context)

        unless r_desc[:actions].empty? && r_desc[:resources].empty?
          ret[:resources][r_name] = r_desc
        end
      end

      ret
    end

    def describe_resource(r, hash, context)
      r.describe(hash, context)
    end

    def version_prefix(v)
      "#{@root}v#{v}/"
    end

    def add_auth_module(v, name, mod, prefix: '')
      @routes[v] ||= {authentication: {name => {resources: {}}}}

      HaveAPI.get_version_resources(mod, v).each do |r|
        mount_resource("#{@root}_auth/#{prefix}/", v, r, @routes[v][:authentication][name][:resources])
      end
    end

    # Register a block that will be called for hook +name+.
    # The block is passed arguments depending on hook type.
    # === Hook types
    # ==== :post_authenticated
    # Called after the user was authenticated (or not). The block is passed
    # current user object or nil as an argument.
    def register_hook(name, &block)
      @hooks[name] << block
    end

    def app
      @sinatra
    end

    def start!
      @sinatra.run!
    end

    private
    def do_authenticate(v, request)
      @auth_chain.authenticate(v, request)
    end

    def invoke_hook(name, *args)
      @hooks[name].each do |block|
        block.call(*args)
      end
    end
  end
end
