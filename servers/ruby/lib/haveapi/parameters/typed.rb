require 'date'

module HaveAPI::Parameters
  class Typed
    ATTRIBUTES = %i[label desc type db_name default fill clean protected load_validators].freeze

    attr_reader :name, :label, :desc, :type, :default

    def initialize(name, args = {})
      # The hash values are deleted and it shouldn't affect the received hash
      myargs = args.clone

      @name = name
      @label = myargs.delete(:label) || name.to_s.capitalize
      @layout = :custom

      (ATTRIBUTES - %i[label]).each do |attr|
        instance_variable_set("@#{attr}", myargs.delete(attr))
      end

      @type ||= String

      @validators = HaveAPI::ValidatorChain.new(myargs) unless myargs.empty?
      raise "unused arguments #{myargs}" unless myargs.empty?
    end

    def db_name
      @db_name || @name
    end

    def required?
      @validators ? @validators.required? : false
    end

    def optional?
      !required?
    end

    def fill?
      @fill
    end

    def load_validators?
      @load_validators.nil? || @load_validators
    end

    def describe(context)
      {
        required: required?,
        label: @label,
        description: @desc,
        type: @type ? @type.to_s : String.to_s,
        validators: @validators ? @validators.describe : {},
        default: @default,
        protected: @protected || false
      }
    end

    def add_validator(k, v)
      @validators ||= HaveAPI::ValidatorChain.new({})
      @validators.add_or_replace(k, v)
    end

    def patch(attrs)
      attrs.each do |k, v|
        if ATTRIBUTES.include?(k)
          instance_variable_set("@#{k}", v)

        else
          add_validator(k, v)
        end
      end
    end

    def clean(raw)
      return instance_exec(raw, &@clean) if @clean

      if raw.nil?
        @default

      elsif @type.nil?
        nil

      elsif @type == Integer
        coerce_integer(raw)

      elsif @type == Float
        coerce_float(raw)

      elsif @type == Boolean
        coerce_boolean(raw)

      elsif @type == ::Datetime
        coerce_datetime(raw)

      elsif @type == String || @type == Text
        coerce_string(raw)

      else
        raw
      end
    end

    def validate(v, params)
      @validators ? @validators.validate(v, params) : true
    end

    def format_output(v)
      if v.nil?
        nil

      elsif @type == ::Datetime && v.is_a?(Time)
        v.iso8601

      elsif @type == Boolean
        v ? true : false

      elsif @type == Integer
        v.to_i

      elsif @type == Float
        v.to_f

      elsif @type == String || @type == Text
        v.to_s

      else
        v
      end
    end

    private

    def coerce_integer(raw)
      case raw
      when Integer
        raw
      when Float
        unless raw.finite? && (raw % 1) == 0
          raise HaveAPI::ValidationError, "not a valid integer #{raw.inspect}"
        end

        raw.to_i
      when String
        s = raw.strip

        if s.empty? || !s.match?(/\A[+-]?\d+\z/)
          raise HaveAPI::ValidationError, "not a valid integer #{raw.inspect}"
        end

        Integer(s, 10)
      else
        raise HaveAPI::ValidationError, "not a valid integer #{raw.inspect}"
      end
    end

    def coerce_float(raw)
      if raw.is_a?(Numeric)
        f = raw.to_f

      elsif raw.is_a?(String)
        s = raw.strip
        raise HaveAPI::ValidationError, "not a valid float #{raw.inspect}" if s.empty?

        begin
          f = Float(s)
        rescue ArgumentError
          raise HaveAPI::ValidationError, "not a valid float #{raw.inspect}"
        end

      else
        raise HaveAPI::ValidationError, "not a valid float #{raw.inspect}"
      end

      raise HaveAPI::ValidationError, "not a valid float #{raw.inspect}" unless f.finite?

      f
    end

    def coerce_boolean(raw)
      return true if raw == true
      return false if raw == false

      if raw.is_a?(Integer)
        return false if raw == 0
        return true if raw == 1

      elsif raw.is_a?(String)
        s = raw.strip
        raise HaveAPI::ValidationError, "not a valid boolean #{raw.inspect}" if s.empty?

        return true if %w[true t yes y 1].include?(s.downcase)
        return false if %w[false f no n 0].include?(s.downcase)
      end

      raise HaveAPI::ValidationError, "not a valid boolean #{raw.inspect}"
    end

    def coerce_datetime(raw)
      if raw.is_a?(String) && raw.strip.empty?
        raise HaveAPI::ValidationError, "not in ISO 8601 format '#{raw}'"
      end

      DateTime.iso8601(raw).to_time
    rescue ArgumentError
      raise HaveAPI::ValidationError, "not in ISO 8601 format '#{raw}'"
    end

    def coerce_string(raw)
      if raw.is_a?(Array) || raw.is_a?(Hash)
        raise HaveAPI::ValidationError, "not a valid string #{raw.inspect}"
      end

      raw.to_s
    end
  end
end
