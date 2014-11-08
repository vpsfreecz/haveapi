module HaveAPI
  class Action < Common
    obj_type :action
    has_attr :version
    has_attr :desc
    has_attr :route
    has_attr :resolve, ->(klass){ klass.respond_to?(:id) ? klass.id : nil }
    has_attr :http_method, :get
    has_attr :auth, true
    has_attr :aliases, []

    include Hookable

    has_hook :exec_exception

    attr_reader :message, :errors, :version

    class << self
      attr_reader :resource, :authorization, :examples

      def inherited(subclass)
        # puts "Action.inherited called #{subclass} from #{to_s}"

        subclass.instance_variable_set(:@obj_type, obj_type)

        if subclass.name
          # not an anonymouse class
          delayed_inherited(subclass)
        end
      end

      def delayed_inherited(subclass)
        resource = Kernel.const_get(subclass.to_s.deconstantize)

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
        rescue NoMethodError
          return
        end
      end

      def initialized?
        @initialize
      end

      def initialized
        @initialize = true
      end

      def model_adapter(layout)
        ModelAdapter.for(layout, resource.model)
      end

      def input(layout = nil, namespace: nil, &block)
        if block
          @input ||= Params.new(:input, self)
          @input.layout = layout
          @input.namespace = namespace
          @input.instance_eval(&block)

          model_adapter(@input.layout).load_validators(model, @input) if model
        else
          @input
        end
      end

      def output(layout = nil, namespace: nil, &block)
        if block
          @output ||= Params.new(:output, self)
          @output.layout = layout
          @output.namespace = namespace
          @output.instance_eval(&block)
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
        @examples ||= []
        e = Example.new(title)
        e.instance_eval(&block)
        @examples << e
      end

      def build_route(prefix)
        route = @route || to_s.demodulize.underscore

        if !route.is_a?(String) && route.respond_to?(:call)
          route = route.call(self.resource)
        end

        prefix + route % {resource: self.resource.to_s.demodulize.underscore}
      end

      def describe(context)
        authorization = (@authorization && @authorization.clone) || Authorization.new

        return false if (context.endpoint || context.current_user) && !authorization.authorized?(context.current_user)

        route_method = context.action.http_method.to_s.upcase
        context.authorization = authorization

        if context.endpoint
          context.action_instance = context.action.from_context(context)
          context.action_prepare = context.action_instance.prepare
        end

        {
            auth: @auth,
            description: @desc,
            aliases: @aliases,
            input: @input ? @input.describe(context) : {parameters: {}},
            output: @output ? @output.describe(context) : {parameters: {}},
            meta: @meta ? @meta.merge(@meta) { |_, v| v && v.describe(context) } : nil,
            examples: @examples ? @examples.map { |e| e.describe } : [],
            url: context.resolved_url,
            method: route_method,
            help: "#{context.url}?method=#{route_method}"
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
        end

        ret
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
      @reply_meta = {object: {}, global: {}}

      class_auth = self.class.authorization

      if class_auth
        @authorization = class_auth.clone
      else
        @authorization = Authorization.new {}
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
      ret = catch(:return) do
        begin
          validate!
          prepare
          pre_exec
          exec
        rescue Exception => e
          tmp = call_class_hooks_as_for(Action, :exec_exception, args: [self, e])

          if tmp.empty?
            p e.message
            puts e.backtrace
            error('Server error occurred')
          end

          error(tmp[:message]) unless tmp[:status]
        end
      end

      if ret
        output = self.class.output

        if output
          safe_ret = nil
          adapter = self.class.model_adapter(output.layout)

          case output.layout
            when :object
              out = adapter.output(@context, ret)
              safe_ret = @authorization.filter_output(
                  self.class.output.params,
                  out
              )
              @reply_meta[:global].update(out.meta)

            when :object_list
              safe_ret = []

              ret.each do |obj|
                out = adapter.output(@context, obj)

                safe_ret << @authorization.filter_output(
                    self.class.output.params,
                    out
                )
                safe_ret.last.update({Metadata.namespace => out.meta}) unless meta[:no]
              end

            when :hash
              safe_ret = @authorization.filter_output(
                          self.class.output.params,
                          adapter.output(@context, ret))

            when :hash_list
              safe_ret = ret
              safe_ret.map! do |hash|
                @authorization.filter_output(
                    self.class.output.params,
                    adapter.output(@context, hash))
              end

            else
              safe_ret = ret
          end

          ns = {output.namespace => safe_ret}
          ns[Metadata.namespace] = @reply_meta[:global] unless meta[:no]

          [true, ns]

        else
          [true, {}]
        end

      else
        [false, @message, @errors]
      end
    end

    def v?(v)
      @version == v
    end

    input {}
    output {}
    meta(:global) do
      input do
        bool :no, label: 'Disable metadata'
      end
    end

    protected
    def with_restricted(*args)
      if args.empty?
        @authorization.restrictions
      else
        args.first.update(@authorization.restrictions)
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

    def ok(ret={})
      throw(:return, ret)
    end

    def error(msg, errs={})
      @message = msg
      @errors = errs
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

        # Remove duplicit key
        @safe_params.delete(input.namespace.to_s)

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
