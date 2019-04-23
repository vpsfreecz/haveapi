module HaveAPI::GoClient
  module Utils
    def camelize(v)
      v.to_s.split('_').map(&:capitalize).join('')
    end
  end
end
