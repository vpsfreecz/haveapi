require 'haveapi/validator'

module HaveAPI
  # Checks the length of a string. It does not have a short form.
  #
  # Full form:
  #   string :param, length: {
  #     min: 3,
  #     max: 10
  #     message: 'the error message'
  #   }
  #
  #   string :param, length: {
  #     equals: 8
  #   }
  class Validators::Length < Validator
    name :length
    takes :length

    def setup
      @min = take(:min)
      @max = take(:max)
      @equals = take(:equals)

      if (@min || @max) && @equals
        raise 'cannot mix min/max with equals'

      elsif !@min && !@max && !@equals
        raise 'must use either min, max or equals'
      end

      msg = if @equals
              "length has to be #{@equals}"

            elsif @min && !@max
              "length has to be minimally #{@min}"

            elsif !@min && @max
              "length has to be maximally #{@max}"

            else
              "length has to be in range <#{@min}, #{@max}>"
            end

      @message = take(:message, msg)
    end

    def describe
      ret = {
        message: @message
      }

      if @equals
        ret[:equals] = @equals

      else
        ret[:min] = @min if @min
        ret[:max] = @max if @max
      end

      ret
    end

    def valid?(v)
      len = v.length

      return len == @equals if @equals
      return len >= @min if @min && !@max
      return len <= @max if !@min && @max

      len.between?(@min, @max)
    end
  end
end
