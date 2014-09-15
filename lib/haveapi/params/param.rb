module HaveAPI::Parameters
  class Param
    attr_reader :name, :label, :desc, :type

    def initialize(name, required: nil, label: nil, desc: nil, type: nil,
                   choices: nil, db_name: nil, default: :_nil)
      @required = required
      @name = name
      @label = label || name.to_s.capitalize
      @desc = desc
      @type = type
      @choices = choices
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
          choices: @choices,
          validators: @validators,
          default: @default
      }
    end

    def clean(raw)
      if raw.nil?
        val = @default

      elsif @type.nil?
        val = nil

      elsif @type == Integer
        val = raw.to_i

      elsif @type == Boolean
        val = Boolean.to_b(raw)

      else
        val = raw
      end

      if @choices
        if @choices.is_a?(Array)
          unless @choices.include?(val) || @choices.include?(val.to_sym)
            raise HaveAPI::ValidationError.new("invalid choice '#{raw}'")
          end

        elsif @choices.is_a?(Hash)
          unless @choices.has_key?(val) || @choices.has_key?(val.to_sym)
            raise HaveAPI::ValidationError.new("invalid choice '#{raw}'")
          end
        end
      end

      val
    end
  end
end
