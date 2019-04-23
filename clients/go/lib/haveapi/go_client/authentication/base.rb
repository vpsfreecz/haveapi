module HaveAPI::GoClient
  class Authentication::Base
    def self.register(name)
      AuthenticationMethods.register(name, self)
    end

    def generate(dst)
      raise NotImplementedError
    end
  end
end
