module HaveAPI::Client
  class Validators::Acceptance < Validator
    name :accept

    def valid?
      value == opts[:value]
    end
  end
end
