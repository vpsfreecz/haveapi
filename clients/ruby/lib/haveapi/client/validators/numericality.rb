module HaveAPI::Client
  class Validators::Numericality < Validator
    name :number

    def valid?
      if value.is_a?(::String)
        return false if /\A\d+\z/ !~ value
        v = value.to_i

      else
        v = value
      end

      ret = true
      ret = false if opts[:min] && v < opts[:min]
      ret = false if opts[:max] && v > opts[:max]
      ret = false if opts[:step] && (v - (opts[:min] || 0)) % opts[:step] != 0
      ret = false if opts[:mod] && v % opts[:mod] != 0
      ret = false if opts[:odd] && v % 2 == 0
      ret = false if opts[:even] && v % 2 > 0
      ret
    end
  end
end
