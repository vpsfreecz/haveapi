module HaveAPI::GoClient
  class Authentication::Base
    # @param name [Symbol]
    def self.register(name)
      AuthenticationMethods.register(name, self)
    end

    # @param dst [String]
    def generate(dst)
      raise NotImplementedError
    end
  end
end
