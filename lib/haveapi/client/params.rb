module HaveAPI::Client
  module Parameters ; end

  class Params
    attr_reader :errors, :params

    def initialize(action, data)
      @action = action
      @data = data
      @params = {}
      @errors = {}
      coerce
    end

    def coerce
      @action.input_params.each do |name, p|
        next unless @data.has_key?(name)

        if p[:type] == 'Resource'
          @params[name] = Parameters::Resource.new(self, p, @data[name])

        else
          @params[name] = Parameters::Typed.new(self, p, @data[name])
        end
      end
    end

    def valid?
      @action.input_params.each do |name, p|
        next if p[:validators].nil?

        if p[:validators][:presence] && @params[name].nil?
          error(name, 'required parameter missing')

        elsif @params[name].nil?
          next
        end

        if !@params[name].valid?
          error(name, @params[name].errors)
        end

      end

      @errors.empty?
    end

    def to_api
      ret = {}

      @params.each do |name, p|
        ret[name] = p.to_api
      end

      ret[:meta] = @data[:meta] if @data.has_key?(:meta)

      ret
    end

    protected
    def error(param, msg)
      @errors[param] ||= []

      if msg.is_a?(::Array)
        @errors[param].concat(msg)

      else
        @errors[param] << msg
      end
    end
  end
end
