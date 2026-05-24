require 'date'
require 'time'

module HaveAPI::Parameters
  class Typed
    ATTRIBUTES = %i[
      label desc type db_name default fill clean protected load_validators
      nullable symbolize_keys
    ].freeze

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

    def nullable?
      @nullable == true && optional?
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
        nullable: nullable?,
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
      clean_raw = custom? ? normalize_custom_keys(raw) : raw
      return validate_cleaned_value(instance_exec(clean_raw, &@clean)) if @clean

      if raw.nil?
        return nil if nullable?

        raise HaveAPI::ValidationError, 'cannot be null'
      end

      if raw.is_a?(String)
        stripped = strip_string(raw)
        return nil if stripped.empty? && nullable?
      end

      if @type.nil?
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

      elsif custom?
        clean_raw

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

    def validate_cleaned_value(value)
      if value.nil? && !nullable?
        raise HaveAPI::ValidationError, 'cannot be null'
      end

      value
    end

    def custom?
      @type == Custom
    end

    def normalize_custom_keys(value)
      case value
      when ::Hash
        value.each_with_object({}) do |(key, inner), ret|
          ret[normalize_custom_key(key)] = normalize_custom_keys(inner)
        end
      when ::Array
        value.map { |inner| normalize_custom_keys(inner) }
      else
        value
      end
    end

    def normalize_custom_key(key)
      if @symbolize_keys
        key.respond_to?(:to_sym) ? key.to_sym : key.to_s.to_sym
      else
        key.to_s
      end
    end

    def strip_string(value)
      value.strip
    rescue ArgumentError, Encoding::CompatibilityError
      raise HaveAPI::ValidationError, 'invalid string encoding'
    end

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
        s = strip_string(raw)

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
        s = strip_string(raw)
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
        s = strip_string(raw)
        raise HaveAPI::ValidationError, "not a valid boolean #{raw.inspect}" if s.empty?

        return true if %w[true t yes y 1].include?(s.downcase)
        return false if %w[false f no n 0].include?(s.downcase)
      end

      raise HaveAPI::ValidationError, "not a valid boolean #{raw.inspect}"
    end

    def coerce_datetime(raw)
      unless raw.is_a?(String)
        raise HaveAPI::ValidationError, "not in ISO 8601 format '#{raw}'"
      end

      if strip_string(raw).empty?
        raise HaveAPI::ValidationError, "not in ISO 8601 format '#{raw}'"
      end

      DateTime.iso8601(raw).to_time
    rescue ArgumentError, TypeError
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
