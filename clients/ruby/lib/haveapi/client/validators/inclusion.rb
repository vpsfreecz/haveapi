require 'haveapi/client/validator'

module HaveAPI::Client
  class Validators::Inclusion < Validator
    name :include

    def valid?
      if opts[:values].is_a?(::Hash)
        opts[:values].keys.any? { |v| v.to_s == value.to_s }

      else
        opts[:values].include?(value)
      end
    end
  end
end
