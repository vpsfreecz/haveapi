module HaveAPI::Client
  class Validators::Presence < Validator
    name :present

    def valid?
      return false if value.nil?
      return !value.strip.empty? if !opts[:empty] && value.is_a?(::String)
      true
    end
  end
end
