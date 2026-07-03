require 'haveapi/validator'

module HaveAPI
  # Checks that the value is not reserved.
  #
  # Short form:
  #   string :param, exclude: %i(one two three)
  #
  # Full form:
  #   string :param, exclude: {
  #     values: %i(one two three),
  #     message: 'the error message'
  #   }
  #
  # In this case, the value could be anything but `one`, `two` or
  # `three`.
  class Validators::Exclusion < Validator
    name :exclude
    takes :exclude

    def setup
      @values = (simple? ? take : take(:values)).map! do |v|
        v.is_a?(::Symbol) ? v.to_s : v
      end

      @message = take(:message, HaveAPI.message('haveapi.validators.exclusion.excluded'))
    end

    def describe
      {
        values: @values,
        message: HaveAPI.localize(@message)
      }
    end

    def valid?(v)
      !@values.include?(v)
    end
  end
end
