module HaveAPI::GoClient
  module Utils
    # Remove underscores and capitalize names
    # @param v [String]
    # @return [String]
    def camelize(v)
      v.to_s.split('_').map(&:capitalize).join('')
    end
  end
end
