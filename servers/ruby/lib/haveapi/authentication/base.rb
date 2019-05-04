module HaveAPI
  module Authentication
    # Base class for authentication providers.
    class Base
      attr_accessor :name

      def initialize(server, v)
        @server = server
        @version = v
        setup
      end

      # @return [Module, nil]
      def resource_module
        nil
      end

      # Reimplement this method in your authentication provider.
      # +request+ is passed directly from Sinatra.
      def authenticate(request)

      end

      # Reimplement to describe provider.
      def describe
        {}
      end

      protected
      # Called during API mount.
      def setup

      end

      # Immediately return from authentication chain.
      # User is not allowed to authenticate.
      def deny
        throw(:return)
      end
    end
  end
end
