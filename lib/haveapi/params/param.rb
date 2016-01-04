module HaveAPI::Parameters
  class Param
    attr_reader :name, :label, :desc, :type, :default

    def initialize(name, args = {})
      @name = name
      @label = args.delete(:label) || name.to_s.capitalize
      @layout = :custom

      %i(label desc type db_name default fill clean).each do |attr|
        instance_variable_set("@#{attr}", args.delete(attr))
      end

      @type ||= String

      @validators = HaveAPI::ValidatorChain.new(args) unless args.empty?
      fail "unused arguments #{args}" unless args.empty?
    end

    def db_name
      @db_name || @name
    end

    def required?
      @validators ? @validators.required? : false
    end

    def optional?
      !@required
    end

    def fill?
      @fill
    end

    def describe(context)
      {
          required: required?,
          label: @label,
          description: @desc,
          type: @type ? @type.to_s : String.to_s,
          validators: @validators ? @validators.describe : {},
          default: @default
      }
    end

    def add_validator(*args)

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

      val
    end

    def validate(v, params)
      @validators ? @validators.validate(v, params) : true
    end

    def format_output(v)
      if @type == ::Datetime && v.is_a?(Time)
        v.iso8601

      else
        v
      end
    end
  end
end
