# Just to represent boolean type in self-description
module Boolean
  def self.to_b(str)
    return true if str === true
    return false if str === false

    if str.respond_to?(:=~)
      return true if str =~ /^(true|t|yes|y|1)$/i
      return false if str =~ /^(false|f|no|n|0)$/i
    end

    false
  end
end

module Datetime

end

module Custom

end

class Text < String

end
