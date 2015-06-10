module HaveAPI::Parameters
  class Param
    attr_reader :name, :label, :desc, :type, :default

    def initialize(name, required: nil, label: nil, desc: nil, type: nil,
                   choices: nil, db_name: nil, default: :_nil, fill: false,
                   clean: nil)
      @required = required
      @name = name
      @label = label || name.to_s.capitalize
      @desc = desc
      @type = type
      @choices = choices
      @db_name = db_name
      @default = default
      @fill = fill
      @layout = :custom
      @validators = {}
      @clean = clean
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

    def fill?
      @fill
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

    def patch(attrs)
      attrs.each { |k, v| instance_variable_set("@#{k}", v) }
    end

    def clean(raw)
      return instance_exec(raw, &@clean) if @clean

      val = if raw.nil?
        @default

      elsif @type.nil?
        nil

      elsif @type == Integer
        raw.to_i

      elsif @type == Boolean
        Boolean.to_b(raw)

      elsif @type == ::Datetime
        begin
          Time.iso8601(raw)

        rescue ArgumentError
          raise HaveAPI::ValidationError.new("not in ISO 8601 format '#{raw}'")
        end

      else
        raw
      end

      if @choices
        if @choices.is_a?(Array)
          unless @choices.include?(val) || @choices.include?(val.to_s.to_sym)
            raise HaveAPI::ValidationError.new("invalid choice '#{raw}'")
          end

        elsif @choices.is_a?(Hash)
          unless @choices.has_key?(val) || @choices.has_key?(val.to_s.to_sym)
            raise HaveAPI::ValidationError.new("invalid choice '#{raw}'")
          end
        end
      end

      val
    end
  end
end
