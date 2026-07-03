require 'erb'
require 'redcarpet'
require 'tilt'
require 'cgi'
require 'haveapi/hooks'

module HaveAPI
  class Server
    attr_accessor :default_version, :action_state, :validation_error_http_status,
                  :default_locale, :parameter_i18n_scope
    attr_reader :root, :routes, :module_name, :auth_chain, :versions, :extensions,
                :action_state_auth, :locale_header, :available_locales

    include Hookable

    has_hook :pre_mount,
             desc: 'Called before API actions are mounted in sinatra',
             args: {
               server: 'HaveAPI::Server',
               sinatra: 'Sinatra::Base'
             }

    has_hook :post_mount,
             desc: 'Called after API actions are mounted in sinatra',
             args: {
               server: 'HaveAPI::Server',
               sinatra: 'Sinatra::Base'
             }

    # Called after the user was authenticated (or not). The block is passed
    # current user object or nil as an argument.
    has_hook :post_authenticated,
             desc: 'Called after the user was authenticated',
             args: {
               current_user: 'object returned by the authentication backend'
             }

    has_hook :description_exception,
             desc: 'Called when an exception occurs when building self-description',
             args: {
               context: 'HaveAPI::Context',
               exception: 'exception instance'
             },
             ret: {
               http_status: 'HTTP status code to send to client',
               message: 'error message sent to the client'
             }

    has_hook :request_exception,
             desc: 'Called when an exception occurs outside action execution',
             args: {
               context: 'HaveAPI::Context',
               exception: 'exception instance'
             },
             ret: {
               http_status: 'HTTP status code to send to client',
               message: 'error message sent to the client'
             }

    module ServerHelpers
      def setup_request_locale
        return if @haveapi_locale_setup

        server = settings.api_server
        @haveapi_previous_locale = ::I18n.locale
        locale_header_value = server.locale_header_value(request)
        @haveapi_locale_requested = !locale_header_value.nil?
        @haveapi_explicit_locale = server.request_locale(request)
        @haveapi_locale = if @haveapi_locale_requested
                            @haveapi_explicit_locale || server.default_locale
                          else
                            server.resolved_locale(
                              request:,
                              current_user: nil
                            )
                          end
        server.activate_locale(@haveapi_locale)
        add_vary_header(server.locale_header) if server.locale_header
        @haveapi_locale_setup = true
      end

      def resolve_request_locale(user = current_user)
        setup_request_locale
        return @haveapi_locale if @haveapi_locale_requested

        @haveapi_locale = settings.api_server.resolved_locale(
          request:,
          current_user: user
        )
        settings.api_server.activate_locale(@haveapi_locale)
      end

      def restore_request_locale
        return unless @haveapi_locale_setup

        settings.api_server.activate_locale(@haveapi_previous_locale)
      end

      def add_vary_header(name)
        values = response['Vary'].to_s.split(/\s*,\s*/).reject(&:empty?)
        values << name unless values.include?(name)
        headers 'Vary' => values.join(', ')
      end

      def setup_formatter
        return if @formatter

        @formatter = OutputFormatter.new
        accept = request.accept
      rescue ArgumentError, EncodingError
        @formatter.supports?([])
        report_error(400, {}, HaveAPI.message('haveapi.errors.bad_accept_header'))
      else
        unless @formatter.supports?(accept)
          @halted = true
          halt 406, "Not Acceptable\n"
        end

        content_type @formatter.content_type, charset: 'utf-8'
      end

      def authenticate!(v)
        require_auth! unless authenticated?(v)
      end

      def authenticated?(v)
        if @current_user
          resolve_request_locale
          return @current_user
        end

        begin
          @current_user = settings.api_server.send(:do_authenticate, v, request)
        rescue HaveAPI::Authentication::TokenConflict => e
          unless @formatter
            @formatter = OutputFormatter.new
            @formatter.supports?([])
          end

          report_error(400, {}, e.message)
        end
        settings.api_server.call_hooks_for(:post_authenticated, args: [@current_user])
        resolve_request_locale
        @current_user
      end

      def authenticated_versions
        ret = settings.api_server.versions.each_with_object({}) do |v, users|
          users[v] = settings.api_server.send(:do_authenticate, v, request)
        rescue HaveAPI::Authentication::TokenConflict => e
          unless @formatter
            @formatter = OutputFormatter.new
            @formatter.supports?([])
          end

          report_error(400, {}, e.message)
        end

        resolve_request_locale(ret[settings.api_server.default_version] || ret.values.compact.first)
        ret
      end

      def access_control
        return unless request.env['HTTP_ORIGIN'] && request.env['HTTP_ACCESS_CONTROL_REQUEST_METHOD']

        halt 200, {
          'access-control-allow-origin' => '*',
          'access-control-allow-methods' => 'GET,POST,OPTIONS,PATCH,PUT,DELETE',
          'access-control-allow-credentials' => 'false',
          'access-control-allow-headers' => settings.api_server.allowed_headers,
          'access-control-max-age' => (60 * 60).to_s
        }, ''
      end

      def current_user
        @current_user
      end

      def pretty_format(obj)
        ret = ''
        PP.pp(obj, ret)
      end

      def require_auth!
        report_error(
          401,
          { 'www-authenticate' => 'Basic realm="Restricted Area"' },
          HaveAPI.message('haveapi.authentication.required')
        )
      end

      def report_error(code, headers, msg)
        @halted = true
        unless @formatter
          @formatter = OutputFormatter.new
          @formatter.supports?([])
        end

        content_type @formatter.content_type, charset: 'utf-8'
        halt code, headers, @formatter.format(false, nil, msg, version: false)
      end

      def report_exception(exception, context = nil)
        context ||= Context.new(
          settings.api_server,
          request: self,
          params:,
          endpoint: true
        )

        tmp =
          begin
            settings.api_server.call_hooks_for(
              :request_exception,
              args: [context, exception]
            )
          rescue StandardError => e
            warn "HaveAPI request exception hook failed: #{e.class}: #{e.message}"
            {}
          end

        report_error(
          tmp[:http_status] || 500,
          {},
          tmp[:message] || HaveAPI.message('haveapi.errors.server_error')
        )
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

      def base_url
        scheme = if request.env['HTTP_X_FORWARDED_SSL'] == 'on'
                   'https'

                 else
                   request.env['rack.url_scheme']
                 end

        "#{scheme}://#{request.env['HTTP_HOST']}"
      end

      def host
        request.env['HTTP_HOST'].split(':').first
      end

      def urlescape(v)
        CGI.escape(v)
      end

      def sort_hash(hash)
        hash.sort { |a, b| a[0] <=> b[0] }
      end

      def api_version
        @v
      end

      def version
        HaveAPI::VERSION
      end
    end

    module DocHelpers
      def format_param_type(param)
        return param[:type] if param[:type] != 'Resource'

        "<a href=\"#root-#{param[:resource].join('-')}-show\">#{param[:type]}</a>"
      end

      def format_validators(validators)
        ret = ''
        return ret if validators.nil?

        validators.each do |name, opts|
          ret += "<h5>#{escape_html(name.to_s.capitalize)}</h5>"
          ret += '<dl>'
          if opts.respond_to?(:each_pair)
            opts.each_pair do |k, v|
              ret += "<dt>#{escape_html(k)}</dt><dd>#{escape_html(v.to_s)}</dd>"
            end
          else
            ret += "<dt>description</dt><dd>#{escape_html(opts.to_s)}</dd>"
          end
          ret += '</dl>'
        end

        ret
      end

      def escape_html(v)
        return '' if v.nil?

        CGI.escapeHTML(v.to_s)
      end
    end

    def initialize(module_name = HaveAPI.module_name)
      @module_name = module_name
      @allowed_headers = ['Content-Type']
      @auth_chain = HaveAPI::Authentication::Chain.new(self)
      @extensions = []
      @action_state_auth = :backend
      @validation_error_http_status = nil
      @default_locale = :en
      self.available_locales = HaveAPI::I18n.available_locales
      self.locale_header = 'Accept-Language'
    end

    def available_locales=(locales)
      @available_locales = Array(locales)
      allow_i18n_locales(@available_locales)
    end

    def locale_header=(header)
      @locale_header = header
      allow_header(header) if header
    end

    def activate_locale(locale)
      allow_i18n_locales([locale])
      ::I18n.locale = locale
    end

    def allow_i18n_locales(locales)
      requested = Array(locales).compact.map { |locale| locale.to_s.to_sym }
      current = ::I18n.available_locales
      missing = requested.reject do |locale|
        current.any? { |available| available.to_s == locale.to_s }
      end

      ::I18n.available_locales = current + missing unless missing.empty?
    end

    def locale(&block)
      @locale_resolver = block if block
      @locale_resolver
    end

    def request_locale(request)
      HaveAPI::I18n.accept_language(
        locale_header_value(request),
        available_locales
      )
    end

    def locale_header_value(request)
      request.env["HTTP_#{locale_header.to_s.upcase.tr('-', '_')}"]
    end

    def resolved_locale(request:, current_user:)
      locale = if @locale_resolver
                 @locale_resolver.call(
                   request:,
                   current_user:,
                   default_locale:
                 )
               end

      HaveAPI::I18n.normalize_locale(locale, available_locales) || default_locale
    end

    def action_state_auth=(mode)
      @action_state_auth = case mode
                           when :backend, false, nil
                             :backend
                           when :required, true
                             :required
                           else
                             raise ArgumentError, "unsupported action_state_auth #{mode.inspect}"
                           end
    end

    # Include specific version `v` of API.
    #
    # `default` is set only when including concrete version. Use {set_default_version}
    # otherwise.
    #
    # @param v [:all, Array<String>, String]
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

    # Load routes for all resource from included API versions.
    # All routes are mounted under prefix `path`.
    # If no default version is set, the last included version is used.
    def mount(prefix = '/')
      @root = prefix

      @sinatra = Sinatra.new do
        # Preload template engine for .md -- without this, tilt will not search
        # for markdown files with extension .md, only .markdown
        Tilt[:md]

        set :views, "#{settings.root}/views"
        set :public_folder, "#{settings.root}/public"
        set :bind, '0.0.0.0'

        if settings.development?
          set :dump_errors, true
          set :raise_errors, true
          set :show_exceptions, false
        end

        helpers Sinatra::Cookies
        helpers ServerHelpers
        helpers DocHelpers

        before do
          setup_request_locale

          if request.env['HTTP_ORIGIN']
            headers 'access-control-allow-origin' => '*',
                    'access-control-allow-credentials' => 'false'
          end
        end

        not_found do
          setup_formatter
          report_error(404, {}, HaveAPI.message('haveapi.errors.action_not_found')) unless @halted
        end

        error do
          report_exception(env['sinatra.error'])
        end

        after do
          restore_request_locale

          if Object.const_defined?(:ActiveRecord)
            ActiveRecord::Base.connection_handler.clear_active_connections!
          end
        end
      end

      @sinatra.set(:api_server, self)

      @routes = {}
      @default_version ||= @versions.last

      # Mount root
      @sinatra.get @root do
        auth_users_by_version = authenticated_versions

        @api = settings.api_server.describe(Context.new(
                                              settings.api_server,
                                              user: auth_users_by_version[settings.api_server.default_version],
                                              params:,
                                              auth_users_by_version:
                                            ))

        content_type 'text/html'
        erb :index, layout: :main_layout
      end

      @sinatra.options @root do
        setup_formatter
        access_control
        ret = nil

        ret = case params[:describe]
              when 'versions'
                {
                  versions: settings.api_server.versions,
                  default: settings.api_server.default_version
                }

              when 'default'
                auth_users_by_version = authenticated_versions

                settings.api_server.describe_version(Context.new(
                                                       settings.api_server,
                                                       version: settings.api_server.default_version,
                                                       user: auth_users_by_version[settings.api_server.default_version],
                                                       doc: true,
                                                       params:,
                                                       auth_users_by_version:
                                                     ))

              else
                auth_users_by_version = authenticated_versions

                settings.api_server.describe(Context.new(
                                               settings.api_server,
                                               user: auth_users_by_version[settings.api_server.default_version],
                                               doc: true,
                                               params:,
                                               auth_users_by_version:
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
          markdown File.new("#{settings.views}/../../../README.md").read
        end
      end

      @sinatra.get "#{@root}doc/json-schema" do
        content_type 'text/html'
        erb :doc_layout, layout: :main_layout do
          @content = File.read(File.join(settings.root, '../../doc/json-schema.html'))
          @sidebar = erb :'doc_sidebars/json-schema'
        end
      end

      @sinatra.get %r{#{@root}doc/([^.]+)(\.md)?} do |f, _|
        content_type 'text/html'
        erb :doc_layout, layout: :main_layout do
          begin
            @content = doc(f)
          rescue Errno::ENOENT
            halt 404
          end

          begin
            @sidebar = erb :"doc_sidebars/#{f}"
          rescue Errno::ENOENT
            @sidebar = ''
          end
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

      @extensions.each { |e| e.enabled(self) }

      call_hooks_for(:pre_mount, args: [self, @sinatra])

      # Mount default version first
      mount_version(@root, @default_version)

      @versions.each do |v|
        mount_version(version_prefix(v), v)
      end

      call_hooks_for(:post_mount, args: [self, @sinatra])
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
                                                       params:
                                                     ))

        content_type 'text/html'
        erb :doc_layout, layout: :main_layout do
          @content = erb :version_page
          @sidebar = erb :version_sidebar
        end
      end

      @sinatra.options prefix do
        setup_formatter
        access_control
        authenticated?(v)

        @formatter.format(true, settings.api_server.describe_version(Context.new(
                                                                       settings.api_server,
                                                                       version: v,
                                                                       user: current_user,
                                                                       doc: true,
                                                                       params:
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
        r[:actions].each_key(&:validate_build)

        validate_resources(r[:resources])
      end
    end

    def collect_parameter_metadata_i18n_items(resources, context)
      resources.flat_map do |resource, children|
        original_resource_path = context.resource_path
        context.resource_path = context.resource_path + [resource.resource_name.underscore]

        action_items = children[:actions].flat_map do |action, path|
          context.action = action
          context.path = path

          action.parameter_metadata_i18n_items(context)
        end

        child_items = collect_parameter_metadata_i18n_items(children[:resources], context)

        action_items + child_items
      ensure
        context.resource_path = original_resource_path
      end
    end
    private :collect_parameter_metadata_i18n_items

    def mount_resource(prefix, v, resource, hash)
      hash[resource] = { resources: {}, actions: {} }

      resource.routes(prefix).each do |route|
        if route.is_a?(Hash)
          hash[resource][:resources][route.keys.first] = mount_nested_resource(
            v,
            route.values.first
          )

        else
          hash[resource][:actions][route.action] = route.path
          mount_action(v, route)
        end
      end
    end

    def mount_nested_resource(v, routes)
      ret = { resources: {}, actions: {} }

      routes.each do |route|
        if route.is_a?(Hash)
          ret[:resources][route.keys.first] = mount_nested_resource(v, route.values.first)

        else
          ret[:actions][route.action] = route.path
          mount_action(v, route)
        end
      end

      ret
    end

    def mount_action(v, route)
      @sinatra.method(route.http_method).call(route.sinatra_path) do
        context = nil

        begin
          setup_formatter

          if route.action.auth || settings.api_server.action_state_auth_required?(route)
            authenticate!(v)
          else
            authenticated?(v)
          end

          raw_body = request.body ? request.body.read : ''
          body_method = !%i[get head options].include?(route.http_method.to_sym)

          if body_method && !raw_body.empty? && !settings.api_server.send(:json_content_type?, request)
            report_error(415, {}, HaveAPI.message('haveapi.errors.unsupported_content_type'))
          end

          begin
            body = raw_body.empty? ? nil : JSON.parse(raw_body)
          rescue JSON::ParserError
            report_error(400, {}, HaveAPI.message('haveapi.errors.bad_json_syntax'))
          end

          if !raw_body.empty? && !body.is_a?(Hash)
            report_error(400, {}, HaveAPI.message('haveapi.errors.json_body_object'))
          end

          action_params = settings.api_server.send(:path_params, route, params)
          action_input = body_method ? (body || {}) : request.GET

          context = Context.new(
            settings.api_server,
            version: v,
            request: self,
            action: route.action,
            path: route.path,
            path_params: action_params,
            input: action_input,
            user: current_user,
            endpoint: true,
            resource_path: route.resource_path
          )

          action = route.action.new(request, v, action_params, action_input, context)

          unless action.authorized?(current_user)
            report_error(403, {}, HaveAPI.message('haveapi.authorization.insufficient_permissions'))
          end

          status, reply, errors, http_status = action.safe_exec
          @halted = true

          [
            http_status || 200,
            @formatter.format(
              status,
              status ? reply : nil,
              status ? nil : reply,
              errors,
              version: false
            )
          ]
        rescue Exception => e # rubocop:disable Lint/RescueException
          report_exception(e, context)
        end
      end

      @sinatra.options route.sinatra_path do |*args|
        ctx = nil

        begin
          setup_formatter
          access_control
          route_method = route.http_method.to_s.upcase

          pass if params[:method] && params[:method] != route_method

          if route.action.auth || settings.api_server.action_state_auth_required?(route)
            authenticate!(v)
          else
            authenticated?(v)
          end

          ctx = Context.new(
            settings.api_server,
            version: v,
            request: self,
            action: route.action,
            path: route.path,
            args:,
            params:,
            user: current_user,
            endpoint: true,
            resource_path: route.resource_path,
            doc: true
          )

          begin
            desc = route.action.describe(ctx)

            unless desc
              report_error(403, {}, HaveAPI.message('haveapi.authorization.insufficient_permissions'))
            end
          rescue ValidationError => e
            report_error(400, e.to_hash, e.message_value)
          rescue StandardError => e
            tmp = settings.api_server.call_hooks_for(:description_exception, args: [ctx, e])
            report_error(
              tmp[:http_status] || 500,
              {},
              tmp[:message] || HaveAPI.message('haveapi.errors.server_error')
            )
          end

          @formatter.format(true, desc)
        rescue Exception => e # rubocop:disable Lint/RescueException
          report_exception(e, ctx)
        end
      end
    end

    def describe(context)
      original_user = context.current_user
      auth_users_by_version = context.auth_users_by_version
      authenticated_description = auth_users_by_version&.values&.any?

      ret = { default_version: @default_version, versions: {} }

      context.version = @default_version
      context.current_user = auth_users_by_version ? auth_users_by_version[@default_version] : original_user
      ret[:versions][:default] = describe_version(context) unless authenticated_description && context.current_user.nil?

      @versions.each do |v|
        user = auth_users_by_version ? auth_users_by_version[v] : original_user
        next if authenticated_description && user.nil?

        context.version = v
        context.current_user = user
        ret[:versions][v] = describe_version(context)
      end

      ret
    ensure
      context.current_user = original_user
    end

    def describe_version(context)
      ret = {
        authentication: @auth_chain.describe(context),
        resources: {},
        meta: Metadata.describe,
        help: version_prefix(context.version)
      }

      # puts JSON.pretty_generate(@routes)

      @routes[context.version][:resources].each do |resource, children|
        r_name = resource.resource_name.underscore
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

    def parameter_metadata_i18n_items(version: @default_version)
      routes = @routes.fetch(version)
      context = Context.new(self, version:, doc: true)

      collect_parameter_metadata_i18n_items(routes[:resources], context)
    end

    def path_for_action(version, action)
      routes = @routes && @routes[version]
      return unless routes

      find_action_path(routes[:resources], action)
    end

    def action_state_auth_required?(route)
      return false unless route.action.resource == HaveAPI::Resources::ActionState
      return false if @auth_chain.empty?

      @action_state_auth == :required
    end

    def version_prefix(v)
      "#{@root}v#{v}/"
    end

    # @param v [String] API version
    # @param provider [Authentication::Base]
    # @param prefix [String]
    def add_auth_routes(v, provider, prefix: '', global: false)
      provider.register_routes(@sinatra, auth_prefix(v, prefix, global:))
    end

    def add_auth_module(v, name, mod, prefix: '', global: false)
      @routes[v] ||= { authentication: { name => { resources: {} } } }

      HaveAPI.get_version_resources(mod, v).each do |r|
        mount_resource("#{auth_prefix(v, prefix, global:)}/", v, r, @routes[v][:authentication][name][:resources])
      end
    end

    def auth_prefix(v, prefix, global:)
      root = global ? "#{@root}_auth" : "#{version_prefix(v)}_auth"
      "#{root}/#{prefix}"
    end

    def json_content_type?(request)
      media_type = if request.respond_to?(:media_type)
                     request.media_type
                   else
                     request.content_type.to_s.split(';').first
                   end

      media_type == 'application/json' || media_type.to_s.end_with?('+json')
    end

    def path_params(route, params)
      route.action.path_param_names(route.path).each_with_object({}) do |name, ret|
        value = if params.has_key?(name.to_sym)
                  params[name.to_sym]
                elsif params.has_key?(name)
                  params[name]
                end

        next if value.nil?

        ret[name] = value
        ret[name.to_sym] = value
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

    def find_action_path(resources, action)
      resources.each_value do |node|
        path = node[:actions][action]
        return path if path

        path = find_action_path(node[:resources], action)
        return path if path
      end

      nil
    end
  end
end
