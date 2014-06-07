module HaveAPI
  class Action < Common
    obj_type :action
    has_attr :version
    has_attr :desc
    has_attr :route
    has_attr :http_method, :get
    has_attr :auth, true

    attr_reader :message, :errors

    def self.inherited(subclass)
      #puts "Action.inherited called #{subclass} from #{to_s}"

      subclass.instance_variable_set(:@obj_type, obj_type)

      resource = Kernel.const_get(subclass.to_s.deconstantize)

      inherit_attrs(subclass)
      inherit_attrs_from_resource(subclass, resource, [:auth])

      begin
        subclass.instance_variable_set(:@resource, resource)
        subclass.instance_variable_set(:@model, resource.model)
      rescue NoMethodError
        return
      end
    end

    class << self
      attr_reader :resource, :authorization, :input, :output

      def input(layout = :object, namespace: nil, &block)
        if block
          @input = Params.new(:input, self, layout, namespace)
          @input.instance_eval(&block)
          @input.load_validators(model) if model
        else
          @input
        end
      end

      def output(layout = :object, namespace: nil, &block)
        if block
          @output = Params.new(:output, self, layout, namespace)
          @output.instance_eval(&block)
        else
          @output
        end
      end

      def authorize(&block)
        @authorization = Authorization.new(&block)
      end

      def example(&block)
        if block
          @example = Example.new
          @example.instance_eval(&block)
        else
          @example
        end
      end

      def build_route(prefix)
        prefix + (@route || to_s.demodulize.underscore) % {resource: self.resource.to_s.demodulize.underscore}
      end

      def describe(context)
        authorization = (@authorization && @authorization.clone) || Authorization.new

        return false if (context.endpoint || context.current_user) && !authorization.authorized?(context.current_user)

        route_method = context.action.http_method.to_s.upcase
        context.authorization = authorization

        {
            auth: @auth,
            description: @desc,
            input: @input ? @input.describe(context) : {parameters: {}},
            output: @output ? @output.describe(context) : {parameters: {}},
            example: @example ? @example.describe : {},
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
        ret = new(c.version, c.params, nil)
        ret.instance_exec do
          @authorization = c.authorization
        end
        ret.validate!
        ret
      end
    end

    def initialize(version, params, body)
      @version = version
      @params = params
      @params.update(body) if body

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

    # Prepare objects, set instance variables from URL parameters.
    # This method does not return anything, it should only setup environment.
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
          case output.layout
            when :object
              ret = resourcify(@authorization.filter_output(self.class.output.params, ret))

            when :list
              ret.map! do |obj|
                resourcify(@authorization.filter_output(self.class.output.params, obj))
              end
          end

          [true, {output.namespace => ret}]

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

      m.reflections.each_key do |name|
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

    def resourcify(hash)
      self.class.output.params.each do |p|
        next unless p.is_a?(Parameters::Resource) && hash[p.name]

        tmp = hash[p.name]

        hash[p.name] = {
            p.value_id => tmp.method(p.value_id).call,
            p.value_label => tmp.method(p.value_label).call
        }
      end

      hash
    end
  end
end
