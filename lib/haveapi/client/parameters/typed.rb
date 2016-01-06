module HaveAPI::Client
  class Parameters::Typed
    module Boolean
      def self.to_b(str)
        return true if str === true
        return true if str =~ /^(true|t|yes|y|1)$/i

        return false if str === false
        return false if str =~ /^(false|f|no|n|0)$/i

        false
      end
    end

    attr_reader :errors, :value

    def initialize(params, desc, value)
      @params = params
      @desc = desc
      @value = coerce(value)
      @errors = []
    end

    def valid?
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
      type = @desc[:type]

      val = if type == 'Integer'
        raw.to_i

      elsif type == 'Float'
        raw.to_f

      elsif type == 'Boolean'
        Boolean.to_b(raw)

      elsif type == 'Datetime'
        begin
          Time.iso8601(raw)

        rescue ArgumentError
          @errors << 'not in ISO 8601 format'
          nil
        end

      elsif type == 'String'
        raw.to_s

      else
        raw
      end

      val
    end
  end
end
