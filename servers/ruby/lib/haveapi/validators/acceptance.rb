require 'haveapi/validator'

module HaveAPI
  # Accepts a single configured value.
  #
  # Short form:
  #   string :param, accept: 'value'
  #
  # Full form:
  #   string :param, accept: {
  #     value: 'value',
  #     message: 'the error message'
  #   }
  class Validators::Acceptance < Validator
    name :accept
    takes :accept

    def setup
      @value = if simple?
                 take

               else
                 take(:value)
               end

      @message = take(
        :message,
        HaveAPI.message('haveapi.validators.acceptance.accepted', value: @value)
      )
    end

    def describe
      {
        value: @value,
        message: HaveAPI.localize(@message)
      }
    end

    def valid?(v)
      v == @value
    end
  end
end
