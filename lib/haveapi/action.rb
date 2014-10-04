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

    attr_reader :message, :errors
    class << self
      attr_reader :resource, :authorization, :input, :output, :examples

      def inherited(subclass)
        # puts "Action.inherited called #{subclass} from #{to_s}"

        subclass.instance_variable_set(:@obj_type, obj_type)

        resource = Kernel.const_get(subclass.to_s.deconstantize)

        inherit_attrs(subclass)
        inherit_attrs_from_resource(subclass, resource, [:auth])

        i = @input.clone
        i.action = subclass

        o = @output.clone
        o.action = subclass

        subclass.instance_variable_set(:@input, i)
        subclass.instance_variable_set(:@output, o)

        begin
          subclass.instance_variable_set(:@resource, resource)
          subclass.instance_variable_set(:@model, resource.model)
        rescue NoMethodError
          return
        end
      end

      def input(layout = nil, namespace: nil, &block)
        if block
          @input ||= Params.new(:input, self)
          @input.layout = layout
          @input.namespace = namespace
          @input.instance_eval(&block)
          @input.load_validators(model) if model
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
        prefix + (@route || to_s.demodulize.underscore) % {resource: self.resource.to_s.demodulize.underscore}
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
      @context.action_instance = self

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

    # Prepare object, set instance variables from URL parameters.
    # This method should return queried object. If the method is
    # not implemented or returns nil, action description will not
    # contain link to an associated resource.
    # --
    # FIXME: is this correct behaviour?
    # ++
    def prepare

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
          exec
        rescue ActiveRecord::RecordNotFound => e
          if /find ([^\s]+)[^=]+=(\d+)/ =~ e.message
            error("object #{$~[1]} = #{$~[2]} not found")
          else
            error("object not found: #{e.to_s}")
          end
        end
      end

      if ret
        output = self.class.output

        if output
          safe_ret = nil

          case output.layout
            when :object
              safe_ret = {}

              if ret.is_a?(ActiveRecord::Base)
                safe_ret = to_param_names(all_attrs(ret), :output)
                safe_ret = resourcify(@authorization.filter_output(self.class.output.params, safe_ret), ret)
              end

            when :object_list
              safe_ret = []

              ret.each do |obj|
                if obj.is_a?(ActiveRecord::Base)
                  tmp = to_param_names(all_attrs(obj), :output)

                  safe_ret << resourcify(@authorization.filter_output(self.class.output.params, tmp), obj)
                end
              end

            when :hash
              safe_ret = @authorization.filter_output(self.class.output.params, to_param_names(ret))

            when :hash_list
              safe_ret = ret
              safe_ret.map! do |hash|
                @authorization.filter_output(self.class.output.params, to_param_names(hash))
              end

            else
              safe_ret = ret
          end

          [true, {output.namespace => safe_ret}]

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

    def all_attrs(m)
      ret = m.attributes

      m.class.reflections.each_key do |name|
        ret[name] = m.method(name).call
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
      @safe_params = @params.dup
      input = self.class.input

      if input
        # First check layout
        input.check_layout(@safe_params)

        # Then filter allowed params
        @safe_params[input.namespace] = @authorization.filter_input(self.class.input.params, @safe_params[input.namespace])

        # Remove duplicit key
        @safe_params.delete(input.namespace.to_s)

        # Now check required params, convert types and set defaults
        input.validate(@safe_params)
      end
    end

    def resourcify(hash, klass)
      self.class.output.params.each do |p|
        next unless p.is_a?(Parameters::Resource) && hash[p.name]

        res_out = p.show_action.output

        tmp = hash[p.name]

        val_url = @context.url_with_params(p.resource::Show, klass.method(p.name).call)
        val_method = p.resource::Show.http_method.to_s.upcase

        hash[p.name] = {
            p.value_id => tmp.send(res_out[p.value_id].db_name),
            p.value_label => tmp.send(res_out[p.value_label].db_name),
            :url => val_url,
            :method => val_method,
            :help => "#{val_url}?method=#{val_method}"
        }
      end

      hash
    end
  end
end