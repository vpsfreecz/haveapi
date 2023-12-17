require 'haveapi/validator'

module HaveAPI
  # Checks the value is a number or a string containing only digits.
  #
  # Full form:
  #   string :param, number: {
  #     min: 3,
  #     max: 10,
  #     step: 2,
  #     message: 'the error message'
  #   }
  #
  # Will allow values `3`, `5`, `7` and `9`.
  #
  #   string :param, number: {
  #     min: 3,
  #     max: 10,
  #     mod: 2,
  #   }
  #
  # Will allow values `4`, `6`, `8` and `10`.
  class Validators::Numericality < Validator
    name :number
    takes :number

    def setup
      @min = take(:min)
      @max = take(:max)
      @step = take(:step)
      @mod = take(:mod)
      @even = take(:even)
      @odd = take(:odd)

      msg = if @min && !@max
        "has to be minimally #{@min}"

      elsif !@min && @max
        "has to be maximally #{@max}"

      elsif @min && @max
        "has to be in range <#{@min}, #{@max}>"

      else
        'has to be a number'
      end

      if @step
        msg += '; ' unless msg.empty?
        msg += "in steps of #{@step}"
      end

      if @mod
        msg += '; ' unless msg.empty?
        msg += "mod #{@step} must equal zero"
      end

      if @odd
        msg += '; ' unless msg.empty?
        msg += "odd"
      end

      if @even
        msg += '; ' unless msg.empty?
        msg += "even"
      end

      if @odd && @even
        fail 'cannot be both odd and even at the same time'
      end

      @message = take(:message, msg)
    end

    def describe
      ret = {
        message: @message,
      }

      ret[:min] = @min if @min
      ret[:max] = @max if @max
      ret[:step] = @step if @step
      ret[:mod] = @mod if @mod
      ret[:odd] = @odd if @odd
      ret[:even] = @even if @even

      ret
    end

    def valid?(v)
      if v.is_a?(::String)
        return false if /\A\d+\z/ !~ v
        v = v.to_i
      end

      ret = true
      ret = false if @min && v < @min
      ret = false if @max && v > @max
      ret = false if @step && (v - (@min || 0)) % @step != 0
      ret = false if @mod && v % @mod != 0
      ret = false if @odd && v % 2 == 0
      ret = false if @even && v % 2 > 0
      ret
    end
  end
end
