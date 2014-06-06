module HaveAPI::Parameters
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

    def describe(context)
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
end
