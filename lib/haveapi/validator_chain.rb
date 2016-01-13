module HaveAPI
  # A chain of validators for one input parameter.
  class ValidatorChain
    def initialize(args)
      @validators = []
      @required = false

      find_validators(args) do |validator|
        obj = validator.use(args)
        @required = true if obj.is_a?(Validators::Presence)
        @validators << obj
      end
    end

    # Adds validator that takes option +name+ with configuration in +opt+.
    # If such validator already exists, it is reconfigured with newly provided
    # +opt+.
    #
    # If +opt+ is +nil+, the validator is removed.
    def add_or_replace(name, opt)
      args = { name => opt }

      unless v_class = find_validator(args)
        fail "validator for '#{opt}' not found"
      end

      if v_class == Validators::Presence
        @required = opt.nil? ? false : true
      end

      exists = @validators.detect { |v| v.is_a?(v_class) }

      if exists
        if opt.nil?
          @validators.delete(exists)

        else
          exists.reconfigure(name, opt)
        end

      else
        @validators << v_class.use(args)
      end
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

    # Validate +value+ using all configured validators. It returns
    # either +true+ if the value passed all validators or an array
    # of errors.
    def validate(value, params)
      ret = []

      @validators.each do |validator|
        next if validator.validate(value, params)
        ret << validator.message % {
            value: value
        }
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
