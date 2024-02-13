module HaveAPI
  module Parameters
  end

  class ValidationError < Exception
    def initialize(msg, errors = {})
      @msg = msg
      @errors = errors
    end

    def message
      @msg
    end

    def to_hash
      @errors
    end
  end

  class Params
    attr_reader :params
    attr_accessor :action

    def initialize(direction, action)
      @direction = direction
      @params = []
      @action = action
      @cache = {}
      @blocks = []
    end

    def add_block(b)
      @blocks << b
    end

    def exec
      @blocks.each do |b|
        instance_exec(&b)
      end
    end

    def clone
      obj = super
      params = @params
      blocks = @blocks

      obj.instance_eval do
        @params = params.dup
        @cache = {}
        @blocks = blocks.dup
      end

      obj
    end

    def layout
      return @cache[:layout] if @cache[:layout]

      @cache[:layout] = @layout || :object
    end

    def layout=(l)
      @layout = l if l
    end

    def namespace
      return @cache[:namespace] unless @cache[:namespace].nil?
      return @cache[:namespace] = @namespace unless @namespace.nil?

      n = @action.resource.resource_name.underscore
      n = n.pluralize if %i[object_list hash_list].include?(layout)
      @cache[:namespace] = n.to_sym
    end

    def namespace=(n)
      @namespace = false if n === false
      @namespace = n.to_sym if n
    end

    def requires(name, **kwargs)
      add_param(name, apply(kwargs, required: true))
    end

    def optional(name, **kwargs)
      add_param(name, apply(kwargs, required: false))
    end

    def string(name, **kwargs)
      add_param(name, apply(kwargs, type: String))
    end

    def text(name, **kwargs)
      add_param(name, apply(kwargs, type: Text))
    end

    def password(name, **kwargs)
      add_param(name, apply(kwargs, type: String, protected: true))
    end

    def bool(name, **kwargs)
      add_param(name, apply(kwargs, type: Boolean))
    end

    def integer(name, **kwargs)
      add_param(name, apply(kwargs, type: Integer))
    end

    alias id integer
    alias foreign_key integer

    def float(name, **kwargs)
      add_param(name, apply(kwargs, type: Float))
    end

    def datetime(name, **kwargs)
      add_param(name, apply(kwargs, type: Datetime))
    end

    def param(name, **kwargs)
      add_param(name, kwargs)
    end

    def use(name, include: nil, exclude: nil)
      @include_back ||= []
      @exclude_back ||= []

      block = @action.resource.params(name)

      return unless block

      @include_back << @include.clone if @include
      @exclude_back << @exclude.clone if @exclude

      if include
        @include ||= []
        @include.concat(include)
      end

      if exclude
        @exclude ||= []
        @exclude.concat(exclude)
      end

      instance_eval(&block)

      @include = @include_back.pop if @include
      @exclude = @exclude_back.pop if @exclude
    end

    def resource(name, **kwargs)
      add_resource(name, kwargs)
    end

    alias references resource
    alias belongs_to resource

    def patch(name, **changes)
      @params.detect { |p| p.name == name }.patch(changes)
    end

    # Action returns custom data.
    def custom(name, **kwargs, &block)
      add_param(name, apply(kwargs, type: Custom, clean: block))
    end

    def describe(context)
      context.layout = layout

      ret = { parameters: {} }
      ret[:layout] = layout
      ret[:namespace] = namespace
      ret[:format] = @structure if @structure

      @params.each do |p|
        ret[:parameters][p.name] = p.describe(context)
      end

      ret[:parameters] = if @direction == :input
                           context.authorization.filter_input(
                             @params,
                             ModelAdapters::Hash.output(context, ret[:parameters])
                           )
                         else
                           context.authorization.filter_output(
                             @params,
                             ModelAdapters::Hash.output(context, ret[:parameters])
                           )
                         end

      ret
    end

    def validate_build
      m = :"validate_build_#{@direction}"

      @params.each do |p|
        p.send(m) if p.respond_to?(m)
      end
    end

    # First step of validation. Check if input is in correct namespace
    # and has a correct layout.
    def check_layout(params)
      if (params[namespace].nil? || !valid_layout?(params)) && any_required_params?
        raise ValidationError.new('invalid input layout', {})
      end

      case layout
      when :object, :hash
        params[namespace] ||= {}

      when :object_list, :hash_list
        params[namespace] ||= []
      end
    end

    # Third step of validation. Check if all required params are present,
    # convert params to correct data types, set default values if necessary.
    def validate(params)
      errors = {}

      layout_aware(params) do |input|
        # First run - coerce values to correct types
        @params.each do |p|
          if p.required? && input[p.name].nil?
            errors[p.name] = ['required parameter missing']
            next
          end

          unless input.has_key?(p.name)
            input[p.name] = p.default if p.respond_to?(:fill?) && p.fill?
            next
          end

          begin
            cleaned = p.clean(input[p.name])
          rescue ValidationError => e
            errors[p.name] ||= []
            errors[p.name] << e.message
            next
          end

          input[p.name] = cleaned if cleaned != :_nil
        end

        # Second run - validate parameters
        @params.each do |p|
          next if errors.has_key?(p.name)
          next if input[p.name].nil?

          res = p.validate(input[p.name], input)

          unless res === true
            errors[p.name] ||= []
            errors[p.name].concat(res)
          end
        end
      end

      unless errors.empty?
        raise ValidationError.new('input parameters not valid', errors)
      end

      params
    end

    def [](name)
      @params.detect { |p| p.name == name }
    end

    private

    def add_param(name, kwargs)
      p = Parameters::Typed.new(name, kwargs)

      return if @include && !@include.include?(p.name)
      return if @exclude && @exclude.include?(p.name)

      @params << p unless param_exists?(p.name)
    end

    def add_resource(name, kwargs)
      r = Parameters::Resource.new(name, **kwargs)

      return if @include && !@include.include?(r.name)
      return if @exclude && @exclude.include?(r.name)

      @params << r unless param_exists?(r.name)
    end

    def param_exists?(name)
      !@params.detect { |p| p.name == name }.nil?
    end

    def apply(kwargs, **default)
      kwargs.update(default)
      kwargs
    end

    def valid_layout?(params)
      case layout
      when :object, :hash
        params[namespace].is_a?(Hash)

      when :object_list, :hash_list
        params[namespace].is_a?(Array)

      else
        false
      end
    end

    def layout_aware(params, &)
      ns = namespace

      case layout
      when :object, :hash
        yield(ns ? params[namespace] : params)

      when :object_list, :hash_list
        (ns ? params[namespace] : params).each(&)

      else
        false
      end
    end

    def any_required_params?
      @params.each do |p|
        return true if p.required?
      end

      false
    end
  end
end
