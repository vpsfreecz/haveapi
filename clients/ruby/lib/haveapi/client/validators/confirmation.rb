require 'haveapi/client/validator'

module HaveAPI::Client
  class Validators::Confirmation < Validator
    name :confirm

    def valid?
      other = opts[:parameter].to_sym

      if opts[:equal]
        return false if params[other].nil?

        value == params[other].value

      else
        other = params[other] ? params[other].value : nil
        value != other
      end
    end
  end
end
