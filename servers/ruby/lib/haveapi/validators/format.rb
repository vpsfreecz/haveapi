require 'haveapi/validator'

module HaveAPI
  # Checks that the value is or is not in specified format.
  #
  # Short form:
  #   string :param, format: /^[a-z0-9]+$/
  #
  # Full form:
  #   string :param, format: {
  #     rx: /^[a-z0-9]+$/,
  #     match: true/false,
  #     message: 'the error message'
  #   }
  class Validators::Format < Validator
    name :format
    takes :format

    def setup
      @rx = simple? ? take : take(:rx)
      @match = take(:match, true)
      @desc = take(:desc)
      @message = take(
        :message,
        @desc || HaveAPI.message('haveapi.validators.format.invalid')
      )
    end

    def describe
      {
        rx: @rx.source,
        match: @match,
        description: @desc,
        message: HaveAPI.localize(@message)
      }
    end

    def valid?(v)
      return false unless v.respond_to?(:to_str)

      matched = @rx.match?(v.to_str)

      if @match
        matched

      else
        !matched
      end
    end
  end
end
