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

      requirements = []

      requirements << if @min && !@max
                        HaveAPI.message('haveapi.validators.numericality.min', min: @min)
                      elsif !@min && @max
                        HaveAPI.message('haveapi.validators.numericality.max', max: @max)
                      elsif @min && @max
                        HaveAPI.message('haveapi.validators.numericality.range', min: @min, max: @max)
                      else
                        HaveAPI.message('haveapi.validators.numericality.number')
                      end

      if @step
        requirements << HaveAPI.message('haveapi.validators.numericality.step', step: @step)
      end

      if @mod
        requirements << HaveAPI.message('haveapi.validators.numericality.mod', mod: @mod)
      end

      if @odd
        requirements << HaveAPI.message('haveapi.validators.numericality.odd')
      end

      if @even
        requirements << HaveAPI.message('haveapi.validators.numericality.even')
      end

      if @odd && @even
        raise 'cannot be both odd and even at the same time'
      end

      @message = take(
        :message,
        HaveAPI.message('haveapi.validators.numericality.composite', requirements:)
      )
    end

    def describe
      ret = {
        message: HaveAPI.localize(@message)
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

      return false unless v.is_a?(::Numeric)

      ret = true
      ret = false if @min && v < @min
      ret = false if @max && v > @max
      ret = false if @step && (v - (@min || 0)) % @step != 0
      ret = false if @mod && v % @mod != 0
      ret = false if @odd && v.even?
      ret = false if @even && v % 2 > 0
      ret
    end
  end
end
