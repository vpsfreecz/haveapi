module HaveAPI::GoClient
  module Authentication; end

  module AuthenticationMethods
    # @param name [Symbol]
    # @param klass [Class]
    def self.register(name, klass)
      @methods ||= {}
      @methods[name] = klass
    end

    # @param name [String]
    def self.get(name)
      @methods[name.to_sym]
    end

    # @param api_version [ApiVersion]
    # @param name [String]
    def self.new(api_version, name, *)
      klass = get(name) || Authentication::Unsupported
      klass.new(api_version, name, *)
    end
  end
end
