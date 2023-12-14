require 'haveapi/common'
require 'haveapi/hooks'
require 'haveapi/metadata'

module HaveAPI
  class Action < Common
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
      desc: 'Called to provide additional authorization blocks. These blocks are '+
            'called before action\'s own authorization block. Note that if any '+
            'of the blocks uses allow/deny rule, it will be the final authorization '+
            'decision and even action\'s own authorization block will not be called.',
      args: {
        context: 'HaveAPI::Context instance',
      },
      ret: {
        blocks: 'array of authorization blocks',
      }

    has_hook :exec_exception,
        desc: 'Called when unhandled exceptions occurs during Action.exec',
        args: {
            context: 'HaveAPI::Context instance',
            exception: 'exception instance',
        },
        ret: {
            status: 'true or false, indicating whether error should be reported',
            message: 'error message sent to the user',
        }

    attr_reader :message, :errors, :version
    attr_accessor :flags

    class << self
      attr_accessor :resource
      attr_reader :authorization, :examples

      def inherited(subclass)
        # puts "Action.inherited called #{subclass} from #{to_s}"

        subclass.instance_variable_set(:@obj_type, obj_type)

        if subclass.name
          # not an anonymouse class
          delayed_inherited(subclass)
        end
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

        @meta.each do |k,v|
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
          return
        end
      end

      def initialize
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
                  desc: 'ID of ActionState object for state querying. When null, the action '+
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
          @meta ||= {object: nil, global: nil}
          @meta[type] ||= Metadata::ActionMetadata.new
          @meta[type].action = self
          @meta[type].instance_exec(&block)
        else
          @meta[type]
        end
      end

      def authorize(&block)
        @authorization = Authorization.new(&block)
      end

      def example(title = '', &block)
        @examples ||= ExampleList.new
        e = Example.new(title)
        e.instance_eval(&block)
        @examples << e
      end

      def action_name
        (@action_name ? @action_name.to_s : to_s).demodulize
      end

      def action_name=(name)
        @action_name = name
      end

      def build_route(prefix)
        route = @route || action_name.underscore
          if @route
            @route
          elsif action_name
            action_name.to_s.demodulize.underscore
          else
            to_s.demodulize.underscore
          end

        if !route.is_a?(String) && route.respond_to?(:call)
          route = route.call(self.resource)
        end

        prefix + route % {resource: self.resource.resource_name.underscore}
      end

      def describe(context)
        authorization = (@authorization && @authorization.clone) || Authorization.new

        return false if (context.endpoint || context.current_user) && !authorization.authorized?(context.current_user)

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
            input: @input ? @input.describe(context) : {parameters: {}},
            output: @output ? @output.describe(context) : {parameters: {}},
            meta: @meta ? @meta.merge(@meta) { |_, v| v && v.describe(context) } : nil,
            examples: @examples ? @examples.describe(context) : [],
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
        ret = new(nil, c.version, c.params, nil, c)
        ret.instance_exec do
          @safe_params = @params.dup
          @authorization = c.authorization
          @current_user = c.current_user
        end

        ret
      end

      def resolve_path_params(object)
        if self.resolve
          self.resolve.call(object)

        else
          object.respond_to?(:id) ? object.id : nil
        end
      end
    end

    def initialize(request, version, params, body, context)
      @request = request
      @version = version
      @params = params
      @params.update(body) if body
      @context = context
      @context.action = self.class
      @context.action_instance = self
      @metadata = {}
      @reply_meta = {object: {}, global: {}}
      @flags = {}

      class_auth = self.class.authorization

      if class_auth
        @authorization = class_auth.clone
      else
        @authorization = Authorization.new {}
      end

      ret = call_class_hooks_as_for(
        Action,
        :pre_authorize,
        args: [@context],
        initial: {blocks: []},
      )

      ret[:blocks].reverse_each do |block|
        @authorization.prepend_block(block)
      end
    end

    def validate!
      begin
        @params = validate
      rescue ValidationError => e
        error(e.message, e.to_hash)
      end
    end

    def authorized?(user)
      @current_user = user
      @authorization.authorized?(user)
    end

    def current_user
      @current_user
    end

    def params
      @safe_params
    end

    def input
      @safe_params[ self.class.input.namespace ] if self.class.input
    end

    def request
      @request
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
    def prepare

    end

    def pre_exec

    end

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
        begin
          validate!
          prepare
          pre_exec
          exec
        rescue Exception => e
          tmp = call_class_hooks_as_for(Action, :exec_exception, args: [@context, e])

          if tmp.empty?
            p e.message
            puts e.backtrace
            error('Server error occurred')
          end

          unless tmp[:status]
            error(tmp[:message], {}, http_status: tmp[:http_status] || 500)
          end
        end
      end

      begin
        output_ret = safe_output(exec_ret)
      rescue Exception => e
        tmp = call_class_hooks_as_for(Action, :exec_exception, args: [@context, e])

        p e.message
        puts e.backtrace

        return [
          tmp[:status] || false,
          tmp[:message] || 'Server error occurred',
          {},
          tmp[:http_status] || 500,
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
              @reply_meta[:global].update(out.meta)

            when :object_list
              safe_ret = []

              ret.each do |obj|
                out = adapter.output(@context, obj)

                safe_ret << @authorization.filter_output(
                    out_params,
                    out,
                    true
                )
                safe_ret.last.update({Metadata.namespace => out.meta}) unless meta[:no]
              end

            when :hash
              safe_ret = @authorization.filter_output(
                  out_params,
                  adapter.output(@context, ret),
                  true
              )

            when :hash_list
              safe_ret = ret
              safe_ret.map! do |hash|
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

          ns = {output.namespace => safe_ret}
          ns[Metadata.namespace] = @reply_meta[:global] unless meta[:no]

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
    def to_db_names(hash, src=:input)
      return {} unless hash

      params = self.class.method(src).call.params
      ret = {}

      hash.each do |k, v|
        k = k.to_sym
        hit = false

        params.each do |p|
          if k == p.name
            ret[p.db_name] = v
            hit = true
            break
          end
        end

        ret[k] = v unless hit
      end

      ret
    end

    # Convert DB names to corresponding parameter names.
    # By default, output parameters are used for the translation.
    def to_param_names(hash, src=:output)
      return {} unless hash

      params = self.class.method(src).call.params
      ret = {}

      hash.each do |k, v|
        k = k.to_sym
        hit = false

        params.each do |p|
          if k == p.db_name
            ret[p.name] = v
            hit = true
            break
          end
        end

        ret[k] = v unless hit
      end

      ret
    end

    # @param ret [Hash] response
    # @param opts [Hash] options
    # @option opts [Integer] http_status HTTP status code sent to the client
    def ok(ret = {}, opts = {})
      @http_status = opts[:http_status]
      throw(:return, ret)
    end

    # @param msg [String] error message sent to the client
    # @param errs [Hash<Array>] parameter errors sent to the client
    # @param opts [Hash] options
    # @option opts [Integer] http_status HTTP status code sent to the client
    def error(msg, errs = {}, opts = {})
      @message = msg
      @errors = errs
      @http_status = opts[:http_status]
      throw(:return, false)
    end

    private
    def validate
      # Validate standard input
      @safe_params = @params.dup
      input = self.class.input

      if input
        # First check layout
        input.check_layout(@safe_params)

        # Then filter allowed params
        case input.layout
          when :object_list, :hash_list
            @safe_params[input.namespace].map! do |obj|
              @authorization.filter_input(
                  self.class.input.params,
                  self.class.model_adapter(self.class.input.layout).input(obj))
            end

          else
            @safe_params[input.namespace] = @authorization.filter_input(
                self.class.input.params,
                self.class.model_adapter(self.class.input.layout).input(@safe_params[input.namespace]))
        end

        # Now check required params, convert types and set defaults
        input.validate(@safe_params)
      end

      # Validate metadata input
      auth = Authorization.new { allow }
      @metadata = {}

      return if input && %i(object_list hash_list).include?(input.layout)

      [:object, :global].each do |v|
        meta = self.class.meta(v)
        next unless meta

        raw_meta = nil

        [Metadata.namespace, Metadata.namespace.to_s].each do |ns|
          params = v == :object ? (@params[input.namespace] && @params[input.namespace][ns]) : @params[ns]
          next unless params

          raw_meta = auth.filter_input(
              meta.input.params,
              self.class.model_adapter(meta.input.layout).input(params)
          )

          break if raw_meta
        end

        next unless raw_meta

        @metadata.update(meta.input.validate(raw_meta))
      end
    end
  end
end
