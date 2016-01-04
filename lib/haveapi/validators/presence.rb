module HaveAPI
  # Checks the value is a number or a string containing only digits.
  #
  # Short form:
  #   string :param, required: true
  #
  # Full form:
  #   string :param, required: {
  #     empty: true/false,
  #     message: 'the error message'
  #   }
  class Validators::Presence < Validator
    name :present
    takes :required, :present

    def setup
      @empty = take(:empty, false)
      @message = take(
          :message,
          @empty ? 'must be present' : 'must be present and non-empty'
      )
    end

    def describe
      {
          empty: @empty,
          message: @message,
      }
    end

    def valid?(v)
      return false if v.nil?
      return !v.strip.empty? if !@empty && v.is_a?(::String)
      # FIXME: other data types?
      true
    end
  end
end
