module HaveAPI::Client
  module Validators; end

  class Validator
    class << self
      def name(v)
        Validator.register(v, self)
      end

      def register(name, klass)
        @validators ||= {}
        @validators[name] = klass
      end

      def validate(validators, param, other_params)
        ret = []

        validators.each do |name, desc|
          raise "unsupported validator '#{name}'" if @validators[name].nil?

          v = @validators[name].new(desc, param, other_params)
          ret.concat(v.errors) unless v.valid?
        end

        ret.empty? ? true : ret
      end
    end

    attr_reader :value, :params

    def initialize(opts, value, other_params)
      @opts = opts
      @value = value
      @params = other_params.params
    end

    def errors
      @errors || [format(opts[:message], value:)]
    end

    def valid?
      raise NotImplementedError
    end

    protected

    attr_reader :opts

    def error(e)
      @errors ||= []
      @errors << e
    end
  end
end
