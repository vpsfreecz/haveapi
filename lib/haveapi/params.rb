module HaveAPI
  class ValidationError < Exception
    def initialize(msg, errors)
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

  class Param
    attr_reader :name, :label, :desc, :type

    def initialize(name, required: nil, label: nil, desc: nil, type: nil, db_name: nil, default: :_nil)
      @required = required
      @name = name
      @label = label || name.to_s.capitalize
      @desc = desc
      @type = type
      @db_name = db_name
      @default = default
      @layout = :custom
      @validators = {}
    end

    def db_name
      @db_name || @name
    end

    def required?
      @required
    end

    def optional?
      !@required
    end

    def add_validator(v)
      @validators.update(v)
    end

    def validators
      @validators
    end

    def describe
      {
          required: required?,
          label: @label,
          description: @desc,
          type: @type ? @type.to_s : String.to_s,
          validators: @validators,
          default: @default
      }
    end

    def clean(raw)
      if raw.nil?
        @default

      elsif @type.nil?
        nil

      elsif @type == Integer
        raw.to_i

      elsif @type == Boolean
        Boolean.to_b(raw)

      else
        raw
      end
    end
  end

  class Params
    attr_reader :namespace, :layout, :params

    def initialize(direction, action, namespace)
      @direction = direction
      @params = []
      @action = action
      @namespace = namespace.to_sym
      @layout = :object
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

    # Action returns custom data.
    def custom_structure(name, s)
      @namespace = name
      @layout = :custom
      @structure = s
    end

    # Action returns a list of objects.
    def list_of_objects
      @layout = :list
    end

    # Action returns properties describing one object.
    def object
      @layout = :object
    end

    def load_validators(model)
      tr = ValidatorTranslator.new(@params)

      model.validators.each do |validator|
        tr.translate(validator)
      end
    end

    def describe(authorization)
      ret = {parameters: {}}
      ret[:layout] = @layout
      ret[:namespace] = @namespace
      ret[:format] = @structure if @structure

      @params.each do |p|
        ret[:parameters][p.name] = p.describe
      end

      if @direction == :input
        ret[:parameters] = authorization.filter_input(ret[:parameters])
      else
        ret[:parameters] = authorization.filter_output(ret[:parameters])
      end

      ret
    end

    # First step of validation. Check if input is in correct namespace
    # and has a correct layout.
    def check_layout(params)
      if (params[@namespace].nil? || !valid_layout?(params)) && !@params.empty?
        raise ValidationError.new('invalid input layout', {})
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
          end

          cleaned = p.clean(input[p.name])
          input[p.name] = cleaned if cleaned != :_nil
        end
      end

      unless errors.empty?
        raise ValidationError.new('input parameters not valid', errors)
      end

      params
    end

    private
    def add_param(*args)
      @params << Param.new(*args)
    end

    def apply(args, default)
      args << {} unless args.last.is_a?(Hash)
      args.last.update(default)
      args
    end

    def valid_layout?(params)
      case @layout
        when :object
          params[@namespace].is_a?(Hash)

        when :list
          params[@namespace].is_a?(Array)

        else
          false
      end
    end

    def layout_aware(params)
      case @layout
        when :object
          yield(params[@namespace])

        when :list
          params[@namespace].each do |object|
            yield(object)
          end

        else
          false
      end
    end
  end
end
