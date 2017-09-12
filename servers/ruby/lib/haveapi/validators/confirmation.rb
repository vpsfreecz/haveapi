module HaveAPI
  # Checks that two parameters are equal or not equal.
  #
  # Short form:
  #   string :param, confirm: :other_parameter
  #
  # Full form:
  #   string :param, confirm: {
  #     param: :other_parameter,
  #     equal: true/false,
  #     message: 'the error message'
  #   }
  #
  # +equal+ defaults to +true+.
  class Validators::Confirmation < Validator
    name :confirm
    takes :confirm

    def setup
      @param = simple? ? take : take(:param)
      @equal = take(:equal, true)
      @message = take(
        :message,
        @equal ? "must be the same as #{@param}"
               : "must be different from #{@param}"
      )
    end

    def describe
      {
          equal: @equal ? true : false,
          parameter: @param,
          message: @message,
      }
    end

    def valid?(v)
      if @equal
        v == params[@param]

      else
        v != params[@param]
      end
    end
  end
end
