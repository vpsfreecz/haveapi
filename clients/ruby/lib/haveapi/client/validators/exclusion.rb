module HaveAPI::Client
  class Validators::Exclusion < Validator
    name :exclude

    def valid?
      !opts[:values].include?(value)
    end
  end
end
