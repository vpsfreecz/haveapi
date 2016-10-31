require 'erb'
require 'redcarpet'

module HaveAPI
  class Server
    attr_reader :root, :routes, :module_name, :auth_chain, :versions, :default_version,
                :extensions
    attr_accessor :action_state

    include Hookable

    # Called after the user was authenticated (or not). The block is passed
    # current user object or nil as an argument.
    has_hook :post_authenticated,
        desc: 'Called after the user was authenticated',
        args: {
            current_user: 'object returned by the authentication backend',
        }

    module ServerHelpers
      def authenticate!(v)
        require_auth! unless authenticated?(v)
      end

      def authenticated?(v)
        return @current_user if @current_user

        @current_user = settings.api_server.send(:do_authenticate, v, request)
        settings.api_server.call_hooks_for(:post_authenticated, args: @current_user)
        @current_user
      end

      def access_control
        if request.env['HTTP_ORIGIN'] && request.env['HTTP_ACCESS_CONTROL_REQUEST_METHOD']
          halt 200, {
                'Access-Control-Allow-Origin' => '*',
                'Access-Control-Allow-Methods' => 'GET,POST,OPTIONS,PATCH,PUT,DELETE',
                'Access-Control-Allow-Credentials' => 'false',
                'Access-Control-Allow-Headers' => settings.api_server.allowed_headers,
                'Access-Control-Max-Age' => (60*60).to_s
          }, ''
        end
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
        halt code, headers, @formatter.format(false, nil, msg, version: false)
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

      def version
        HaveAPI::VERSION
      end
    end

    def initialize(module_name = HaveAPI.module_name)
      @module_name = module_name
      @allowed_headers = ['Content-Type']
      @auth_chain = HaveAPI::Authentication::Chain.new(self)
      @extensions = []
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
        @versions = HaveAPI.versions(@module_name)
      elsif v.is_a?(Array)
        @versions += v
        @versions.uniq!
      else
        @versions << v
        @default_version = v if default
      end
    end

    # Set default version of API.
    def default_version=(v)
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

          if request.env['HTTP_ORIGIN']
            headers 'Access-Control-Allow-Origin' => '*',
                    'Access-Control-Allow-Credentials' => 'false'
          end
        end

        not_found do
          report_error(404, {}, 'Action not found') unless @halted
        end

        after do
          ActiveRecord::Base.clear_active_connections! if Object.const_defined?(:ActiveRecord)
        end
      end

      @sinatra.set(:api_server, self)

      @routes = {}
      @default_version ||= @versions.last

      # Mount root
      @sinatra.get @root do
        authenticated?(settings.api_server.default_version)

        @api = settings.api_server.describe(Context.new(
            settings.api_server,
            user: current_user,
            params: params
        ))

        content_type 'text/html'
        erb :index, layout: :main_layout
      end

      @sinatra.options @root do
        access_control
        authenticated?(settings.api_server.default_version)
        ret = nil

        case params[:describe]
          when 'versions'
            ret = {
                versions: settings.api_server.versions,
                default: settings.api_server.default_version
            }

          when 'default'
            ret = settings.api_server.describe_version(Context.new(
                settings.api_server,
                version: settings.api_server.default_version,
                user: current_user, params: params
            ))

          else
            ret = settings.api_server.describe(Context.new(
                settings.api_server,
                user: current_user,
                params: params
            ))
        end

        @formatter.format(true, ret)
      end

      # Doc
      @sinatra.get "#{@root}doc" do
        content_type 'text/html'
        erb :main_layout do
          doc(:index)
        end
      end

      @sinatra.get "#{@root}doc/readme" do
        content_type 'text/html'
        erb :main_layout do
          GitHub::Markdown.render(File.new(settings.views + '/../../../README.md').read)
        end
      end
      
      @sinatra.get "#{@root}doc/json-schema" do
        content_type 'text/html'
        erb :doc_layout, layout: :main_layout do
          @content = erb :'../../../doc/json-schema'
          @sidebar = erb :'doc_sidebars/json-schema'
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

          @sidebar = erb :"doc_sidebars/#{f}"
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

      @extensions.each { |e| e.enabled }

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
        @help = settings.api_server.describe_version(Context.new(
            settings.api_server,
            version: v,
            user: current_user,
            params: params
        ))
        content_type 'text/html'
        erb :doc_layout, layout: :main_layout do
          @content = erb :version_page
          @sidebar = erb :version_sidebar
        end
      end

      @sinatra.options prefix do
        access_control
        authenticated?(v)

        @formatter.format(true, settings.api_server.describe_version(Context.new(
            settings.api_server,
            version: v,
            user: current_user,
            params: params
        )))
      end

      # Register blocking resource
      HaveAPI.get_version_resources(@module_name, v).each do |resource|
        mount_resource(prefix, v, resource, @routes[v][:resources])
      end

      if action_state
        mount_resource(
            prefix,
            v,
            HaveAPI::Resources::ActionState,
            @routes[v][:resources]
        )
      end

      validate_resources(@routes[v][:resources])
    end

    def validate_resources(resources)
      resources.each_value do |r|
        r[:actions].each_key do |a|
          a.validate_build
        end

        validate_resources(r[:resources])
      end
    end

    def mount_resource(prefix, v, resource, hash)
      hash[resource] = {resources: {}, actions: {}}

      resource.routes(prefix).each do |route|
        if route.is_a?(Hash)
          hash[resource][:resources][route.keys.first] = mount_nested_resource(
              v,
              route.values.first
          )

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
        if route.action.auth
          authenticate!(v)
        else
          authenticated?(v)
        end

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

        action = route.action.new(request, v, params, body, Context.new(
            settings.api_server,
            version: v,
            action: route.action,
            url: route.url,
            params: params,
            user: current_user,
            endpoint: true
        ))

        unless action.authorized?(current_user)
          report_error(403, {}, 'Access denied. Insufficient permissions.')
        end

        status, reply, errors = action.safe_exec

        @formatter.format(
            status,
            status  ? reply : nil,
            !status ? reply : nil,
            errors,
            version: false
        )
      end

      @sinatra.options route.url do |*args|
        access_control
        route_method = route.http_method.to_s.upcase

        pass if params[:method] && params[:method] != route_method

        if route.action.auth
          authenticate!(v)
        else
          authenticated?(v)
        end

        begin
          desc = route.action.describe(Context.new(
              settings.api_server,
              version: v,
              action: route.action,
              url: route.url,
              args: args,
              params: params,
              user: current_user,
              endpoint: true
          ))

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
          meta: Metadata.describe,
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

    def allow_header(name)
      @allowed_headers << name unless @allowed_headers.include?(name)
      @allowed_headers_str = nil
    end

    def allowed_headers
      return @allowed_headers_str if @allowed_headers_str
      @allowed_headers_str = @allowed_headers.join(',')
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
  end
end
