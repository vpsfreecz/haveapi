module HaveAPI::Client
  class Validators::Format < Validator
    name :format

    def valid?
      rx = Regexp.new(opts[:rx])

      if opts[:match]
        rx.match(value) ? true : false

      else
        rx.match(value) ? false : true
      end
    end
  end
end
