require 'haveapi/validator'

module HaveAPI
  # Checks the value is present and not empty.
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
      return useless if simple? && !take

      @empty = take(:empty, false)
      @message = take(
        :message,
        HaveAPI.message(
          @empty ? 'haveapi.validators.presence.present' : 'haveapi.validators.presence.non_empty'
        )
      )
    end

    def describe
      {
        empty: @empty,
        message: HaveAPI.localize(@message)
      }
    end

    def valid?(v)
      return false if v.nil?
      return !v.strip.empty? if !@empty && v.is_a?(::String)
      return !v.empty? if !@empty && v.respond_to?(:empty?)

      true
    end
  end
end
