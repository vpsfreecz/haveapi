module HaveAPI
  # A chain of validators for one input parameter.
  class ValidatorChain
    def initialize(args)
      @validators = []
      @required = false

      HaveAPI::Validators.constants.select do |v|
        validator = HaveAPI::Validators.const_get(v)

        if validator.use?(args)
          obj = validator.use(args)
          @required = true if obj.is_a?(Validators::Presence)
          @validators << obj
        end
      end
    end

    # Add validator if it does not exist yet.
    def <<(new_v)
      exists = @validators.detect { |v| v.is_a?(new_v.class) }

      fail "validator #{new_v.class} already exists" if exists
      @validators << new_v
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
  end
end
