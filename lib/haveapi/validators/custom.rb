module HaveAPI
  # Custom validator. It has only a short form, taking the description
  # of the validator. This validator passes every value. It is up to the
  # developer to implement the validation in HaveAPI::Action.exec.
  class Validators::Custom < Validator
    name :custom
    takes :validate

    def setup
      @desc = take
    end

    def describe
      @desc
    end

    def valid?(v)
      true
    end
  end
end
