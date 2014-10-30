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

    def initialize(direction, action = nil)
      @direction = direction
      @params = []
      @action = action
      @cache = {}
    end

    def clone
      obj = super
      params = @params

      obj.instance_eval do
        @params = params.dup
        @cache = {}
      end

      obj
    end

    def layout
      return @cache[:layout] if @cache[:layout]

      @cache[:layout] = @layout ? @layout : :object
    end

    def layout=(l)
      @layout = l if l
    end

    def namespace
      return @cache[:namespace] unless @cache[:namespace].nil?
      return @cache[:namespace] = @namespace unless @namespace.nil?

      n = @action.resource.to_s.demodulize.underscore
      n = n.pluralize if %i(object_list hash_list).include?(layout)
      @cache[:namespace] = n.to_sym
    end

    def namespace=(n)
      @namespace = false if n === false
      @namespace = n.to_sym if n
    end

    def requires(*args)
      add_param(*apply(args, required: true))
    end

    def optional(*args)
      add_param(*apply(args, required: true))
    end

    def string(*args)
      add_param(*apply(args, type: String))
    end

    def id(*args)
      integer(*args)
    end

    def foreign_key(*args)
      integer(*args)
    end

    def bool(*args)
      add_param(*apply(args, type: Boolean))
    end

    def integer(*args)
      add_param(*apply(args, type: Integer))
    end

    def datetime(*args)
      add_param(*apply(args, type: Datetime))
    end

    def param(*args)
      add_param(*args)
    end

    def use(name)
      block = @action.resource.params(name)

      instance_eval(&block) if block
    end

    def resource(*args)
      add_resource(*args)
    end

    alias_method :references, :resource
    alias_method :belongs_to, :resource

    def patch(name, changes = {})
      @params.detect { |p| p.name == name }.patch(changes)
    end

    # Action returns custom data.
    def custom_structure(name, s)
      @namespace = name
      @layout = :custom
      @structure = s
    end

    def describe(context)
      context.layout = layout

      ret = {parameters: {}}
      ret[:layout] = layout
      ret[:namespace] = namespace
      ret[:format] = @structure if @structure

      @params.each do |p|
        ret[:parameters][p.name] = p.describe(context)
      end

      if @direction == :input
        ret[:parameters] = context.authorization.filter_input(
                             @params,
                             ModelAdapters::Hash.output(context, ret[:parameters]))
      else
        ret[:parameters] = context.authorization.filter_output(
                             @params,
                             ModelAdapters::Hash.output(context, ret[:parameters]))
      end

      ret
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
    def add_param(*args)
      @params << Parameters::Param.new(*args)
    end

    def add_resource(*args)
      @params << Parameters::Resource.new(*args)
    end

    def apply(args, default)
      args << {} unless args.last.is_a?(Hash)
      args.last.update(default)
      args
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

    def layout_aware(params)
      ns = namespace

      case layout
        when :object, :hash
          yield(ns ? params[namespace] : params)

        when :object_list, :hash_list
          (ns ? params[namespace] : params).each do |object|
            yield(object)
          end

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
