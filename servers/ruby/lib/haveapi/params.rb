module HaveAPI
  module Parameters
  end

  class ValidationError < StandardError
    attr_reader :message_value

    def initialize(msg, errors = {})
      @message_value = msg
      super(msg)
      @errors = errors
    end

    def message
      HaveAPI.localize(@message_value)
    end

    def to_s
      message
    end

    def to_hash
      @errors
    end
  end

  class Params
    attr_reader :params
    attr_accessor :action

    class << self
      def action_i18n_path(context, direction)
        prefix = action_i18n_prefix(context)
        return unless prefix

        "#{prefix}.#{i18n_segment(direction)}"
      end

      def metadata_i18n_path(context, type, direction)
        prefix = action_i18n_prefix(context)
        return unless prefix

        [
          prefix,
          'meta',
          i18n_segment(type),
          i18n_segment(direction)
        ].join('.')
      end

      def i18n_segment(value)
        value.to_s.underscore.downcase.gsub(/[^a-z0-9_]+/, '_').gsub(/\A_+|_+\z/, '')
      end

      private

      def action_i18n_prefix(context)
        return unless context.respond_to?(:resource_path) && context.resource_path
        return unless context.respond_to?(:action) && context.action

        [
          'resources',
          *context.resource_path.map { |segment| i18n_segment(segment) },
          'actions',
          i18n_segment(context.action.action_name)
        ].join('.')
      end
    end

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
      n = if %i[object_list hash_list].include?(layout)
            n.pluralize
          else
            n.singularize
          end

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
        @include.concat(normalize_names(include))
      end

      if exclude
        @exclude ||= []
        @exclude.concat(normalize_names(exclude))
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

    def remove(name)
      i = @params.index { |p| p.name == name }
      raise "Parameter #{name.inspect} not found" if i.nil?

      @params.delete_at(i)
    end

    # Action returns custom data.
    def custom(name, symbolize_keys: false, **kwargs, &block)
      add_param(name, apply(kwargs, type: Custom, clean: block, symbolize_keys:))
    end

    def describe(context, metadata: false, i18n_path: nil)
      context.layout = layout

      ret = { parameters: {} }
      ret[:layout] = layout
      ret[:namespace] = namespace
      ret[:format] = @structure if @structure

      i18n_path ||= self.class.action_i18n_path(context, @direction)

      @params.each do |p|
        ret[:parameters][p.name] = p.describe(context, i18n_path:)
      end

      ret[:parameters] = filtered_description_parameters(context, ret, metadata)

      ret
    end

    def parameter_metadata_i18n_items(context, i18n_path: nil, meta_type: nil)
      i18n_path ||= self.class.action_i18n_path(context, @direction)

      @params.flat_map do |param|
        next [] unless param.respond_to?(:metadata_i18n_catalog_items)

        param.metadata_i18n_catalog_items(context, i18n_path).map do |item|
          item.merge(
            resource_path: Array(context.resource_path).map { |v| self.class.i18n_segment(v) },
            action: self.class.i18n_segment(context.action.action_name),
            direction: self.class.i18n_segment(@direction),
            meta_type: meta_type && self.class.i18n_segment(meta_type)
          )
        end
      end
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
      value = namespace ? params[namespace] : params

      if value.nil?
        raise ValidationError.new(HaveAPI.message('haveapi.validation.invalid_input_layout'), {}) if any_required_params?

      elsif !valid_layout?(value)
        raise ValidationError.new(HaveAPI.message('haveapi.validation.invalid_input_layout'), {})
      end

      return unless namespace

      case layout
      when :object, :hash
        params[namespace] ||= {}

      when :object_list, :hash_list
        params[namespace] ||= []
      end
    end

    # Third step of validation. Check if all required params are present,
    # convert params to correct data types, set default values if necessary.
    def validate(params, context: nil, only: nil)
      errors = {}
      permitted = only && only.map(&:to_sym)

      layout_aware(params) do |input|
        # First run - coerce values to correct types
        @params.each do |p|
          next if permitted && !permitted.include?(p.name)

          if p.required? && input[p.name].nil?
            errors[p.name] = [HaveAPI.message('haveapi.validation.required_parameter_missing')]
            next
          end

          unless input.has_key?(p.name)
            input[p.name] = p.default if p.respond_to?(:fill?) && p.fill?
            next
          end

          begin
            cleaned = if p.method(:clean).arity.abs > 1
                        p.clean(input[p.name], context)
                      else
                        p.clean(input[p.name])
                      end
          rescue ValidationError => e
            errors[p.name] ||= []
            errors[p.name] << e.message_value
            next
          end

          input[p.name] = cleaned if cleaned != :_nil
        end

        # Second run - validate parameters
        @params.each do |p|
          next if permitted && !permitted.include?(p.name)
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
        raise ValidationError.new(HaveAPI.message('haveapi.validation.input_parameters_not_valid'), errors)
      end

      params
    end

    def [](name)
      @params.detect { |p| p.name == name }
    end

    private

    def filtered_description_parameters(context, ret, metadata)
      params = ModelAdapters::Hash.output(context, ret[:parameters])

      if @direction == :input
        context.authorization.filter_input(@params, params)
      elsif metadata
        context.authorization.filter_meta_output(@params, params)
      else
        context.authorization.filter_output(@params, params)
      end
    end

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

    def normalize_names(names)
      names.map { |v| v.is_a?(String) ? v.to_sym : v }
    end

    def valid_layout?(value)
      case layout
      when :object, :hash
        value.is_a?(Hash)

      when :object_list, :hash_list
        value.is_a?(Array) && value.all?(Hash)

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
