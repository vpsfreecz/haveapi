require 'haveapi/client/validator'

module HaveAPI::Client
  class Validators::Inclusion < Validator
    name :include

    def valid?
      if opts[:values].is_a?(::Hash)
        opts[:values].keys.include?(value)

      else
        opts[:values].include?(value)
      end
    end
  end
end
