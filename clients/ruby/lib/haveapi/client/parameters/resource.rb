module HaveAPI::Client
  class Parameters::Resource
    attr_reader :errors

    def initialize(params, desc, value)
      @params = params
      @errors = []
      @desc = desc
      @value = coerce(value)
    end

    def valid?
      @errors.empty?
    end

    def to_api
      @value
    end

    protected

    def coerce(v)
      if v.nil?
        return nil if @desc[:nullable]

        @errors << message('validation.cannot_be_null')
        return nil
      end

      if v.is_a?(::String) && v.strip.empty?
        return nil if @desc[:nullable]

        @errors << message('validation.invalid_resource_id')
        return nil
      end

      if !v.is_a?(::Integer) && /\A\d+\z/ !~ v
        @errors << message('validation.invalid_resource_id')
        nil

      else
        v.to_i
      end
    end

    def message(key, **values)
      @params.send(:message, key, **values)
    end
  end
end
