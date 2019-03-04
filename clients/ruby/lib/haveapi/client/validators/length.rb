require 'haveapi/client/validator'

module HaveAPI::Client
  class Validators::Length < Validator
    name :length

    def valid?
      len = value.length

      return len == opts[:equals] if opts[:equals]
      return len >= opts[:min] if opts[:min] && !opts[:max]
      return len <= opts[:max] if !opts[:min] && opts[:max]
      len >= opts[:min] && len <= opts[:max]
    end
  end
end
