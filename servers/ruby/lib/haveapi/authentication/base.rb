module HaveAPI
  module Authentication
    # Base class for authentication providers.
    class Base
      # Get or set auth method name
      # @param v [Symbol, nil]
      # @return [Symbol]
      def self.auth_method(v = nil)
        if v
          @auth_method = v
        else
          @auth_method || name.split('::')[-2].underscore.to_sym
        end
      end

      # @return [Symbol]
      attr_reader :name

      def initialize(server, v)
        @name = self.class.auth_method
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
