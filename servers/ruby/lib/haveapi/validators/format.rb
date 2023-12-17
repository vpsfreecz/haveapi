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
      @message = take(:message, @desc || '%{value} is not in a valid format')
    end

    def describe
      {
        rx: @rx.source,
        match: @match,
        description: @desc,
        message: @message,
      }
    end

    def valid?(v)
      if @match
        @rx.match(v) ? true : false

      else
        @rx.match(v) ? false : true
      end
    end
  end
end
