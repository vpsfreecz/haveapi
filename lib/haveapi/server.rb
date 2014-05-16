module HaveAPI
  class Server
    attr_reader :root

    module ServerHelpers
      def authenticate!
        require_auth! unless authenticated?
      end

      def authenticated?
        return @current_user if @current_user

        @current_user = settings.api_server.send(:do_authenticate, request)
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
        halt code, headers, JSON.pretty_generate({
                                                     status: false,
                                                     response: nil,
                                                     message: msg
                                                 })
      end

      def root
        settings.api_server.root
      end

      def logout_url
        ret = url("#{root}_logout")
        ret.insert(ret.index('//') + 2, '_log:out@')
      end
    end

    def initialize(module_name = HaveAPI.module_name)
      @module_name = module_name
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

        # This must be called before registering paper trail, or else it will
        # not be logging current user.
        before do
          authenticated?
        end

        register PaperTrail::Sinatra

        helpers ServerHelpers

        not_found do
          report_error(404, {}, 'Action not found')
        end

        after do
          ActiveRecord::Base.clear_active_connections!
        end
      end

      @sinatra.set(:api_server, self)

      @routes = {}

      # Mount root
      @sinatra.get @root do
        @api = settings.api_server.describe(current_user)
        erb :index, layout: :main
      end

      @sinatra.options @root do
        JSON.pretty_generate(settings.api_server.describe(current_user))
      end

      # Login/logout links
      @sinatra.get "#{root}_login" do
        if current_user
          redirect back
        else
          require_auth!
        end
      end

      @sinatra.get "#{root}_logout" do
        require_auth!
      end

      @default_version ||= @versions.last

      # Mount default version first
      mount_version(@root, @default_version)

      @versions.each do |v|
        mount_version(version_prefix(v), v)
      end
    end

    def mount_version(prefix, v)
      @routes[v] = {}

      @sinatra.get prefix do
        @v = v
        @help = settings.api_server.describe_version(v, current_user)
        erb :version, layout: :main
      end

      @sinatra.options prefix do
        JSON.pretty_generate(settings.api_server.describe_version(v, current_user))
      end

      HaveAPI.get_version_resources(@module_name, v).each do |resource|
        @routes[v][resource] = {resources: {}, actions: {}}

        resource.routes(prefix).each do |route|
          if route.is_a?(Hash)
            @routes[v][resource][:resources][route.keys.first] = mount_nested_resource(v, route.values.first)

          else
            @routes[v][resource][:actions][route.action] = route.url
            mount_action(v, route)
          end
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
        authenticate! if route.action.auth

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

        action = route.action.new(v, params, body)

        unless action.authorized?(current_user)
          report_error(403, {}, 'Access denied. Insufficient permissions.')
        end

        status, reply, errors = action.safe_exec
        reply = {
            status: status,
            response: status ? reply : nil,
            message: !status ? reply : nil,
            errors: errors
        }

        JSON.pretty_generate(reply)
      end

      @sinatra.options route.url do
        route_method = route.http_method.to_s.upcase

        pass if params[:method] && params[:method] != route_method

        desc = route.action.describe(current_user)
        desc[:url] = route.url
        desc[:method] = route_method
        desc[:help] = "#{route.url}?method=#{route_method}"

        JSON.pretty_generate(desc)
      end
    end

    def describe(user)
      ret = {
          default_version: @default_version,
          versions: {default: describe_version(@default_version, user)},
      }

      @versions.each do |v|
        ret[:versions][v] = describe_version(v, user)
      end

      ret
    end

    def describe_version(v, user)
      ret = {resources: {}, help: version_prefix(v)}

      #puts JSON.pretty_generate(@routes)

      @routes[v].each do |resource, children|
        r_name = resource.to_s.demodulize.underscore
        r_desc = describe_resource(resource, children, user)

        unless r_desc[:actions].empty? && r_desc[:resources].empty?
          ret[:resources][r_name] = r_desc
        end
      end

      ret
    end

    def describe_resource(r, hash, user)
      ret = {description: r.desc, actions: {}, resources: {}}

      hash[:actions].each do |action, url|
        a_name = action.to_s.demodulize.underscore
        route_method = action.http_method.to_s.upcase

        a_desc = action.describe(user)

        if a_desc
          ret[:actions][a_name] = a_desc
          ret[:actions][a_name].update({
                                           url: url,
                                           method: route_method,
                                           help: "#{url}?method=#{route_method}"
                                       })
        end
      end

      hash[:resources].each do |resource, children|
        ret[:resources][resource.to_s.demodulize.underscore] = describe_resource(resource, children, user)
      end

      ret
    end

    def version_prefix(v)
      "#{@root}v#{v}/"
    end

    def authenticate(&block)
      @authenticate = block
    end

    def app
      @sinatra
    end

    def start!
      @sinatra.run!
    end

    private
    def do_authenticate(request)
      @authenticate.call(request) if @authenticate
    end
  end
end
