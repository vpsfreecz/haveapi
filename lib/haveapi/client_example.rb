module HaveAPI
  module ClientExamples ; end

  class ClientExample
    class << self
      def label(v = nil)
        if v
          @label = v
          HaveAPI::ClientExample.register(self)
        end

        @label
      end

      def code(v = nil)
        @code = v if v
        @code
      end

      def order(v = nil)
        @order = v if v
        @order
      end

      def register(klass)
        @clients ||= []
        @clients << klass
      end

      def init(*args)
        new(*args).init
      end

      def auth(*args)
        new(*args[0..-2]).auth(args.last)
      end

      def example(*args)
        new(*args[0..-2]).example(args.last)
      end

      def clients
        @clients.sort { |a, b| a.order <=> b.order }
      end
    end

    attr_reader :resource_path, :resource, :action_name, :action, :host, :base_url, :version

    def initialize(host, base_url, version, *args)
      @host = host
      @base_url = base_url
      @version = version
      @resource_path, @resource, @action_name, @action = args
    end

    def init

    end

    def auth(method)

    end

    def example(sample)

    end
  end
end
