module HaveAPI::GoClient
  module Authentication ; end

  module AuthenticationMethods
    def self.register(name, klass)
      @methods ||= {}
      @methods[name] = klass
    end

    def self.get(name)
      @methods[name.to_sym]
    end

    def self.new(api_version, name, *args)
      klass = get(name) || Authentication::Unsupported
      klass.new(api_version, name, *args)
    end
  end
end
