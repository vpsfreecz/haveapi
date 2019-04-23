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

    def self.new(name, *args)
      klass = get(name) || Authentication::Unsupported
      klass.new(name, *args)
    end
  end
end
