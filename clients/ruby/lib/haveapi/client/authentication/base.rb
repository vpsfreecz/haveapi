require 'haveapi/client/communicator'

module HaveAPI::Client
  module Authentication
    # Raise this exception when authentication process fails somewhere
    # outside action execution (in which access forbidden is raised from RestClient).
    class AuthenticationFailed < Exception
      def initialize(msg)
        @msg = msg
      end

      def message
        @msg
      end
    end

    # Base class for all authentication providers.
    #
    # Authentication providers may reimplement only methods they need.
    # You do not have to reimplement all methods.
    class Base
      class << self
        # Register this class as authentication provider with +name+.
        # The +name+ must be the same as is used in CLI auth provider (if any)
        # and on server side.
        # All providers have to register.
        def register(name)
          HaveAPI::Client::Communicator.register_auth_method(name, Kernel.const_get(to_s))
        end
      end

      def initialize(communicator, description, opts, &block)
        @communicator = communicator
        @desc = description
        @opts = opts
        @block = block

        setup
      end

      def inspect
        "#<#{self.class.name} @opts=#{@opts.inspect}>"
      end

      # Called right after initialize. Use this method to initialize provider.
      def setup; end

      # Return RestClient::Resource instance. This is mainly for HTTP basic auth.
      def resource; end

      # Called for each request. Returns a hash of query parameters.
      def request_query_params
        {}
      end

      # Called for each request. Returns a hash of parameters send in request
      # body.
      def request_payload
        {}
      end

      # Called for each request. Returns a hash of HTTP headers.
      def request_headers
        {}
      end

      # Returns a hash of auth provider attributes to be saved e.g. in a file
      # to be used later, without the user providing credentials again.
      # You may wish to save a username or password (not recommended), tokens
      # or whatever authentication provider needs to authenticate user
      # without his input.
      def save
        @opts
      end

      # Load auth provider attributes from previous #save call.
      def load(hash)
        @opts = hash
      end
    end
  end
end
