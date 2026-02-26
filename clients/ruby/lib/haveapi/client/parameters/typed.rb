require 'date'

module HaveAPI::Client
  class Parameters::Typed
    attr_reader :errors, :value

    def initialize(params, desc, value)
      @params = params
      @desc = desc
      @errors = []
      @value = coerce(value)
    end

    def valid?
      return false unless @errors.empty?

      ret = Validator.validate(@desc[:validators], @value, @params)

      @errors.concat(ret) unless ret === true
      ret === true
    end

    def to_api
      if @desc[:type] == 'Datetime' && value.is_a?(Time)
        value.iso8601

      else
        value
      end
    end

    protected

    def coerce(raw)
      if raw.nil?
        return nil if @desc[:nullable]

        @errors << 'cannot be null'
        return nil
      end

      if raw.is_a?(::String) && raw.strip.empty? && @desc[:nullable]
        return nil
      end

      type = @desc[:type]

      case type
      when 'Integer'
        coerce_integer(raw)
      when 'Float'
        coerce_float(raw)
      when 'Boolean'
        coerce_boolean(raw)
      when 'Datetime'
        coerce_datetime(raw)
      when 'String', 'Text'
        coerce_string(raw)
      else
        raw
      end
    end

    private

    def coerce_integer(raw)
      case raw
      when ::Integer
        raw

      when ::Float
        return raw.to_i if raw.finite? && raw == raw.to_i

        invalid_integer

      when ::String
        s = raw.strip
        return invalid_integer if s.empty?
        return invalid_integer unless s.match?(/\A[+-]?\d+\z/)

        Integer(s, 10)

      else
        invalid_integer
      end
    rescue ArgumentError
      invalid_integer
    end

    def coerce_float(raw)
      if raw.is_a?(::Numeric)
        value = raw.to_f
        return value if value.finite?

        @errors << 'not a valid float'
        nil

      elsif raw.is_a?(::String)
        s = raw.strip
        return invalid_float if s.empty?

        value = Float(s)
        return value if value.finite?

        invalid_float

      else
        invalid_float
      end
    rescue ArgumentError
      invalid_float
    end

    def coerce_boolean(raw)
      return raw if [true, false].include?(raw)

      if raw.is_a?(::Integer)
        return true if raw == 1
        return false if raw == 0

        return invalid_boolean
      end

      if raw.is_a?(::String)
        s = raw.strip.downcase
        return invalid_boolean if s.empty?

        return true if %w[true t yes y 1].include?(s)
        return false if %w[false f no n 0].include?(s)
      end

      invalid_boolean
    end

    def coerce_datetime(raw)
      case raw
      when ::Time
        raw

      when ::Date, ::DateTime
        raw.to_time

      when ::String
        return invalid_datetime if raw.strip.empty?

        DateTime.iso8601(raw).to_time

      else
        invalid_datetime
      end
    rescue ArgumentError
      invalid_datetime
    end

    def coerce_string(raw)
      return invalid_string if raw.is_a?(::Array) || raw.is_a?(::Hash)

      raw.to_s
    end

    def invalid_integer
      @errors << 'not a valid integer'
      nil
    end

    def invalid_float
      @errors << 'not a valid float'
      nil
    end

    def invalid_boolean
      @errors << 'not a valid boolean'
      nil
    end

    def invalid_datetime
      @errors << 'not in ISO 8601 format'
      nil
    end

    def invalid_string
      @errors << 'not a valid string'
      nil
    end
  end
end
