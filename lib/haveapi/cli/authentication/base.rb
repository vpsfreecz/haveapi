module HaveAPI::CLI
  module Authentication
    # Base class for CLI interface of authentication providers
    class Base
      class << self
        # Register this class as authentication provider with +name+.
        # The +name+ must be the same as is used in client auth provider
        # and on server side.
        # All providers have to register.
        def register(name)
          HaveAPI::CLI::Cli.register_auth_method(name, Kernel.const_get(to_s))
        end
      end

      attr_accessor :communicator

      # Implement this method to add CLI options for auth provider.
      # +opts+ is an instance of OptionParser.
      def options(opts)

      end

      # Implement this method to check if all needed information
      # for successful authentication are provided.
      # Ask the user on stdin if something is missing.
      def validate

      end

      # This method should call HaveAPI::Client::Communicator#authenticate
      # with arguments specific for this authentication provider.
      def authenticate

      end
    end
  end
end