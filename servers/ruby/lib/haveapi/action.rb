require 'haveapi/common'
require 'haveapi/hooks'
require 'haveapi/metadata'

module HaveAPI
  class Action < Common
    PATH_PARAM_PATTERN = /\{([a-zA-Z0-9\-_]+)\}/

    obj_type :action
    has_attr :version
    has_attr :desc
    has_attr :route
    has_attr :resolve
    has_attr :http_method, :get
    has_attr :auth, true
    has_attr :aliases, []
    has_attr :blocking, false

    include Hookable

    has_hook :pre_authorize,
             desc: "Called to provide additional authorization blocks. These blocks are called before action's own authorization block. Note that if any of the blocks uses allow/deny rule, it will be the final authorization decision and even action's own authorization block will not be called.",
             args: {
               context: 'HaveAPI::Context instance'
             },
             ret: {
               blocks: 'array of authorization blocks'
             }

    has_hook :exec_exception,
             desc: 'Called when unhandled exceptions occurs during Action.exec',
             args: {
                 context: 'HaveAPI::Context instance',
                 exception: 'exception instance'
             },
             ret: {
                 status: 'true or false, indicating whether error should be reported',
                 message: 'error message sent to the user'
             }

    attr_reader :message, :errors, :version, :current_user, :request
    attr_accessor :flags

    class << self
      attr_accessor :resource
      attr_reader :authorization, :examples

      def inherited(subclass)
        # puts "Action.inherited called #{subclass} from #{to_s}"
        super
        subclass.instance_variable_set(:@obj_type, obj_type)

        return unless subclass.name

        # not an anonymouse class
        delayed_inherited(subclass)
      end

      def delayed_inherited(subclass)
        resource = subclass.resource || Kernel.const_get(subclass.to_s.deconstantize)

        inherit_attrs(subclass)
        inherit_attrs_from_resource(subclass, resource, [:auth])

        i = @input.clone
        i.action = subclass

        o = @output.clone
        o.action = subclass

        m = {}

        @meta.each do |k, v|
          m[k] = v && v.clone
          next unless v

          m[k].action = subclass
        end

        subclass.instance_variable_set(:@input, i)
        subclass.instance_variable_set(:@output, o)
        subclass.instance_variable_set(:@meta, m)

        begin
          subclass.instance_variable_set(:@resource, resource)
          subclass.instance_variable_set(:@model, resource.model)
          resource.action_defined(subclass)
        rescue NoMethodError
          nil
        end
      end

      def initialize # rubocop:disable Lint/MissingSuper
        return if @initialized

        check_build("#{self}.input") do
          input.exec
          model_adapter(input.layout).load_validators(model, input) if model
        end

        check_build("#{self}.output") do
          output.exec
        end

        model_adapter(input.layout).used_by(:input, self)
        model_adapter(output.layout).used_by(:output, self)

        if blocking
          meta(:global) do
            output do
              integer :action_state_id,
                      label: 'Action state ID',
                      desc: 'ID of ActionState object for state querying. When null, the action ' \
                            'is not blocking for the current invocation.'
            end
          end
        end

        if @meta
          @meta.each_value do |m|
            next unless m

            check_build("#{self}.meta.input") do
              m.input && m.input.exec
            end

            check_build("#{self}.meta.output") do
              m.output && m.output.exec
            end
          end
        end

        @initialized = true
      end

      def validate_build
        check_build("#{self}.input") do
          input.validate_build
        end

        check_build("#{self}.output") do
          output.validate_build
        end
      end

      def model_adapter(layout)
        ModelAdapter.for(layout, resource.model)
      end

      def input(layout = nil, namespace: nil, &block)
        if block
          @input ||= Params.new(:input, self)
          @input.layout = layout
          @input.namespace = namespace
          @input.add_block(block)
        else
          @input
        end
      end

      def output(layout = nil, namespace: nil, &block)
        if block
          @output ||= Params.new(:output, self)
          @output.layout = layout
          @output.namespace = namespace
          @output.add_block(block)
        else
          @output
        end
      end

      def meta(type = :object, &block)
        if block
          @meta ||= { object: nil, global: nil }
          @meta[type] ||= Metadata::ActionMetadata.new
          @meta[type].action = self
          @meta[type].instance_exec(&block)
        else
          @meta[type]
        end
      end

      def authorize(&)
        @authorization = Authorization.new(&)
      end

      def example(title = '', &)
        @examples ||= ExampleList.new
        e = Example.new(title)
        e.instance_eval(&)
        @examples << e
      end

      def action_name
        (@action_name ? @action_name.to_s : to_s).demodulize
      end

      attr_writer :action_name

      def build_route(prefix)
        route = @route || action_name.underscore

        if !route.is_a?(String) && route.respond_to?(:call)
          route = route.call(resource)
        end

        prefix + format(route, resource: resource.resource_name.underscore)
      end

      def describe(context)
        authorization = (@authorization && @authorization.clone) || Authorization.new {}
        add_pre_authorize_blocks(authorization, context)

        if (context.endpoint || context.current_user) \
            && !authorization.authorized?(context.current_user, context.path_params_from_args)
          return false
        end

        route_method = context.action.http_method.to_s.upcase
        context.authorization = authorization

        if context.endpoint
          context.action_instance = context.action.from_context(context)

          ret = catch(:return) do
            context.action_prepare = context.action_instance.prepare
          end

          return false if ret == false
        end

        {
          auth: @auth,
          description: @desc,
          aliases: @aliases,
          blocking: @blocking ? true : false,
          input: @input ? @input.describe(context) : { parameters: {} },
          output: @output ? @output.describe(context) : { parameters: {} },
          meta: @meta ? @meta.merge(@meta) { |_, v| v && v.describe(context) } : nil,
          examples: @examples ? @examples.describe(context) : [],
          scope: context.action_scope,
          path: context.resolved_path,
          method: route_method,
          help: "#{context.path}?method=#{route_method}"
        }
      end

      # Inherit attributes from resource action is defined in.
      def inherit_attrs_from_resource(action, r, attrs)
        begin
          return unless r.obj_type == :resource
        rescue NoMethodError
          return
        end

        attrs.each do |attr|
          action.method(attr).call(r.method(attr).call)
        end
      end

      def from_context(c)
        ret = new(nil, c.version, c.path_params || c.path_params_from_args, c.input || c.params || {}, c)
        ret.instance_exec do
          @safe_input = self.class.input && input_from_params(raw_input_params(self.class.input))
          @authorization = c.authorization
          @current_user = c.current_user
        end

        ret
      end

      def resolve_path_params(object)
        if resolve
          resolve.call(object)

        else
          object.respond_to?(:id) ? object.id : nil
        end
      end

      def path_param_names(path)
        path.scan(PATH_PARAM_PATTERN).map(&:first)
      end

      def path_params(path, args)
        values = args.is_a?(Array) ? args.dup : [args]
        params = {}

        path_param_names(path).each do |name|
          value = values.shift.to_s
          params[name] = value
          params[name.to_sym] = value
        end

        params
      end

      def add_pre_authorize_blocks(authorization, context)
        ret = Action.call_hooks(
          :pre_authorize,
          args: [context],
          initial: { blocks: [] }
        )

        ret[:blocks].reverse_each do |block|
          authorization.prepend_block(block)
        end
      end
    end

    def initialize(request, version, params, input_params, context)
      super()
      @request = request
      @version = version
      @route_params = params.dup
      @raw_input = input_params || {}
      @context = context
      @context.action = self.class
      @context.action_instance = self
      @metadata = {}
      @reply_meta = { object: {}, global: {} }
      @flags = {}

      class_auth = self.class.authorization

      @authorization = if class_auth
                         class_auth.clone
                       else
                         Authorization.new {}
                       end

      self.class.add_pre_authorize_blocks(@authorization, @context)
    end

    def validate!
      validate
    rescue ValidationError => e
      error!(e.message, e.to_hash, http_status: 400)
    end

    def authorized?(user)
      @current_user = user
      @authorization.authorized?(user, path_params)
    end

    def path_params
      @path_params ||= extract_path_params
    end

    def input
      return unless self.class.input

      @safe_input
    end

    def meta
      @metadata
    end

    def set_meta(hash)
      @reply_meta[:global].update(hash)
    end

    # Prepare object, set instance variables from URL parameters.
    # This method should return queried object. If the method is
    # not implemented or returns nil, action description will not
    # contain link to an associated resource.
    # --
    # FIXME: is this correct behaviour?
    # ++
    def prepare; end

    def pre_exec; end

    # This method must be reimplemented in every action.
    # It must not be invoked directly, only via safe_exec, which restricts output.
    def exec
      ['not implemented']
    end

    # Calls exec while catching all exceptions and restricting output only
    # to what user can see.
    # Return array +[status, data|error, errors]+
    def safe_exec
      exec_ret = catch(:return) do
        validate!
        prepare
        pre_exec
        exec
      rescue Exception => e # rubocop:disable Lint/RescueException
        tmp = call_class_hooks_as_for(Action, :exec_exception, args: [@context, e])

        if tmp.empty?
          p e.message
          puts e.backtrace
          error!('Server error occurred', {}, http_status: 500)
        end

        unless tmp[:status]
          error!(tmp[:message], {}, http_status: tmp[:http_status] || 500)
        end
      end

      begin
        output_ret = safe_output(exec_ret)
      rescue Exception => e # rubocop:disable Lint/RescueException
        tmp = call_class_hooks_as_for(Action, :exec_exception, args: [@context, e])

        p e.message
        puts e.backtrace

        return [
          tmp[:status] || false,
          tmp[:message] || 'Server error occurred',
          {},
          tmp[:http_status] || 500
        ]
      end

      output_ret
    end

    def v?(v)
      @version == v
    end

    def safe_output(ret)
      if ret
        output = self.class.output

        if output
          safe_ret = nil
          adapter = self.class.model_adapter(output.layout)
          out_params = self.class.output.params

          case output.layout
          when :object
            out = adapter.output(@context, ret)
            safe_ret = @authorization.filter_output(
              out_params,
              out,
              true
            )
            @reply_meta[:global].update(filtered_object_meta(out.meta, safe_ret))

          when :object_list
            safe_ret = []

            ret.each do |obj|
              out = adapter.output(@context, obj)

              safe_ret << @authorization.filter_output(
                out_params,
                out,
                true
              )
              next if meta[:no]

              safe_ret.last.update({
                Metadata.namespace => filtered_object_meta(out.meta, safe_ret.last)
              })
            end

          when :hash
            safe_ret = @authorization.filter_output(
              out_params,
              adapter.output(@context, ret),
              true
            )

          when :hash_list
            safe_ret = ret.map do |hash|
              @authorization.filter_output(
                out_params,
                adapter.output(@context, hash),
                true
              )
            end

          else
            safe_ret = ret
          end

          if self.class.blocking
            @reply_meta[:global][:action_state_id] = state_id
          end

          ns = { output.namespace => safe_ret }
          ns[Metadata.namespace] = filtered_global_meta unless meta[:no]

          [true, ns]

        else
          [true, {}]
        end

      else
        [false, @message, @errors, @http_status]
      end
    end

    input {}
    output {}
    meta(:global) do
      input do
        bool :no, label: 'Disable metadata'
      end
    end

    protected

    def with_restricted(**kwargs)
      if kwargs.empty?
        @authorization.restrictions
      else
        kwargs.update(@authorization.restrictions)
      end
    end

    # Convert parameter names to corresponding DB names.
    # By default, input parameters are used for the translation.
    def to_db_names(hash, src = :input)
      return {} unless hash

      params = self.class.method(src).call.params
      ret = {}

      hash.each do |k, v|
        k = k.to_sym
        hit = false

        params.each do |p|
          next unless k == p.name

          ret[p.db_name] = v
          hit = true
          break
        end

        ret[k] = v unless hit
      end

      ret
    end

    # Convert DB names to corresponding parameter names.
    # By default, output parameters are used for the translation.
    def to_param_names(hash, src = :output)
      return {} unless hash

      params = self.class.method(src).call.params
      ret = {}

      hash.each do |k, v|
        k = k.to_sym
        hit = false

        params.each do |p|
          next unless k == p.db_name

          ret[p.name] = v
          hit = true
          break
        end

        ret[k] = v unless hit
      end

      ret
    end

    # @param ret [Hash] response
    # @param opts [Hash] options
    # @option opts [Integer] http_status HTTP status code sent to the client
    def ok!(ret = {}, opts = {})
      @http_status = opts[:http_status]
      throw(:return, ret)
    end

    # @param msg [String] error message sent to the client
    # @param errs [Hash<Array>] parameter errors sent to the client
    # @param opts [Hash] options
    # @option opts [Integer] http_status HTTP status code sent to the client
    def error!(msg, errs = {}, opts = {})
      @message = msg
      @errors = errs
      @http_status = opts[:http_status]
      throw(:return, false)
    end

    private

    def validate
      # Validate standard input
      @safe_input = nil
      input = self.class.input

      if input
        raw_params = raw_input_params(input)

        # First check layout
        input.check_layout(raw_params)

        # Then filter allowed params
        @safe_input = case input.layout
                      when :object_list, :hash_list
                        input_from_params(raw_params).map do |obj|
                          @authorization.filter_input(
                            self.class.input.params,
                            self.class.model_adapter(self.class.input.layout).input(obj)
                          )
                        end

                      else
                        @authorization.filter_input(
                          self.class.input.params,
                          self.class.model_adapter(self.class.input.layout).input(
                            input_from_params(raw_params)
                          )
                        )
                      end

        # Now check required params, convert types and set defaults
        input.validate(
          validated_input_params(input),
          context: @context,
          only: @authorization.permitted_input_names(self.class.input.params)
        )
      end

      validate_metadata(input)
    end

    def validate_metadata(input)
      @metadata = {}

      validate_metadata_type(:global, @authorization)
      validate_metadata_type(:object, @authorization, input) if input && !%i[object_list hash_list].include?(input.layout)
    end

    def validate_metadata_type(type, auth, input = nil)
      meta = self.class.meta(type)
      return unless meta && meta.input

      params = metadata_params(type, input)
      params = {} if params.nil?
      meta.input.check_layout(params)

      raw_meta = auth.filter_input(
        meta.input.params,
        self.class.model_adapter(meta.input.layout).input(params)
      )

      @metadata.update(
        meta.input.validate(
          raw_meta,
          context: @context,
          only: auth.permitted_input_names(meta.input.params)
        )
      )
    end

    def metadata_params(type, input)
      case type
      when :global
        fetch_metadata_from(@raw_input)
      when :object
        return unless input && input.namespace

        obj_params = fetch_param(@raw_input, input.namespace)
        fetch_metadata_from(obj_params) if obj_params.is_a?(Hash)
      end
    end

    def raw_input_params(input)
      return @raw_input.dup unless input.namespace

      { input.namespace => fetch_param(@raw_input, input.namespace) }
    end

    def validated_input_params(input)
      input.namespace ? { input.namespace => @safe_input } : @safe_input
    end

    def input_from_params(params)
      input = self.class.input
      return unless input

      input.namespace ? fetch_param(params, input.namespace) : params
    end

    def fetch_param(params, name)
      return unless params
      return params[name] if params.has_key?(name)

      string_name = name.to_s
      return params[string_name] if params.has_key?(string_name)

      nil
    end

    def fetch_metadata_from(params)
      [Metadata.namespace, Metadata.namespace.to_s].each do |ns|
        return params[ns] if params && params.has_key?(ns)
      end

      nil
    end

    # @return <Hash<Symbol, String>> path parameters and their values
    def extract_path_params
      ret = {}

      self.class.path_param_names(@context.path).each do |path_param|
        ret[path_param] = if @route_params.has_key?(path_param)
                            @route_params[path_param]
                          else
                            @route_params[path_param.to_sym]
                          end
      end

      ret
    end

    def filtered_global_meta
      global_meta = self.class.meta(:global)
      return @reply_meta[:global] unless global_meta && global_meta.output

      @authorization.filter_meta_output(
        global_meta.output.params,
        self.class.model_adapter(global_meta.output.layout).output(@context, @reply_meta[:global]),
        true
      )
    end

    def filtered_object_meta(object_meta, safe_object)
      return object_meta if safe_object.has_key?(:id) || safe_object.has_key?('id')

      object_meta.except(:path_params, 'path_params')
    end
  end
end
