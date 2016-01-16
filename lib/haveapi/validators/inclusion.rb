module HaveAPI
  # Checks that the value is from given set of allowed values.
  #
  # Short form:
  #   string :param, choices: %i(one two three)
  #
  # Full form:
  #   string :param, choices: {
  #     values: %i(one two three),
  #     message: 'the error message'
  #   }
  #
  # Option +choices+ is an alias to +include+.
  class Validators::Inclusion < Validator
    name :include
    takes :choices, :include

    def setup
      @values = (simple? ? take : take(:values)).map! do |v|
        v.is_a?(::Symbol) ? v.to_s : v
      end

      @message = take(:message, '%{value} cannot be used')
    end

    def describe
      {
          values: @values,
          message: @message,
      }
    end

    def valid?(v)
      if @values.is_a?(::Hash)
        @values.has_key?(v)

      else
        @values.include?(v)
      end
    end
  end
end
