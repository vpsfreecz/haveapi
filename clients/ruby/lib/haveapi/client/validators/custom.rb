require 'haveapi/client/validator'

module HaveAPI::Client
  class Validators::Custom < Validator
    name :custom

    def valid?
      true
    end
  end
end
