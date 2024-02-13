module HaveAPI
  # A chain of validators for one input parameter.
  class ValidatorChain
    def initialize(args)
      @validators = []
      @required = false

      find_validators(args) do |validator|
        obj = validator.use(args)
        next unless obj.useful?

        @required = true if obj.is_a?(Validators::Presence)
        @validators << obj
      end
    end

    # Adds validator that takes option `name` with configuration in `opt`.
    # If such validator already exists, it is reconfigured with newly provided
    # `opt`.
    #
    # If `opt` is `nil`, the validator is removed.
    def add_or_replace(name, opt)
      args = { name => opt }

      unless (v_class = find_validator(args))
        raise "validator for '#{name}' not found"
      end

      exists = @validators.detect { |v| v.is_a?(v_class) }
      obj = exists

      if exists
        if opt.nil?
          @validators.delete(exists)

        else
          exists.reconfigure(name, opt)
          @validators.delete(exists) unless exists.useful?
        end

      else
        obj = v_class.use(args)
        @validators << obj if obj.useful?
      end

      return unless v_class == Validators::Presence

      @required = !opt.nil? && obj.useful?
    end

    # Returns true if validator Validators::Presence is used.
    def required?
      @required
    end

    def describe
      ret = {}
      @validators.each do |v|
        ret[v.class.name] = v.describe
      end

      ret
    end

    # Validate `value` using all configured validators. It returns
    # either `true` if the value passed all validators or an array
    # of errors.
    def validate(value, params)
      ret = []

      @validators.each do |validator|
        next if validator.validate(value, params)

        ret << (format(validator.message, value:))
      end

      ret.empty? ? true : ret
    end

    protected

    def find_validator(args)
      HaveAPI::Validators.constants.select do |v|
        validator = HaveAPI::Validators.const_get(v)

        return validator if validator.use?(args)
      end

      nil
    end

    def find_validators(args)
      HaveAPI::Validators.constants.select do |v|
        validator = HaveAPI::Validators.const_get(v)

        yield(validator) if validator.use?(args)
      end
    end
  end
end
