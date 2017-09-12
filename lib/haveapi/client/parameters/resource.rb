module HaveAPI::Client
  class Parameters::Resource
    attr_reader :errors

    def initialize(params, desc, value)
      @errors = []
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
      if !v.is_a?(::Integer) && /\A\d+\z/ !~ v
        @errors << 'not a valid resource id'
        nil

      else
        v.to_i
      end
    end
  end
end
