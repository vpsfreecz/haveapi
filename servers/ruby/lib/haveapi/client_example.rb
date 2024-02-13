module HaveAPI
  module ClientExamples; end

  # All client example classes should inherit this class. Depending on the client,
  # the subclass may choose to implement either method `example` or `request` and
  # `response`. `example` should be implemented if the client example shows only
  # the request or the request and response should be coupled together.
  #
  # Methods `example`, `request` and `response` take one argument, the example
  # to describe.
  class ClientExample
    class << self
      # All subclasses have to call this method to set their label and be
      # registered.
      def label(v = nil)
        if v
          @label = v
          HaveAPI::ClientExample.register(self)
        end

        @label
      end

      # Code name is passed to the syntax highligher.
      def code(v = nil)
        @code = v if v
        @code
      end

      # A number used for ordering client examples.
      def order(v = nil)
        @order = v if v
        @order
      end

      def register(klass)
        @clients ||= []
        @clients << klass
      end

      # Shortcut to {ClientExample#init}
      def init(*)
        new(*).init
      end

      # Shortcut to {ClientExample#auth}
      def auth(*args)
        new(*args[0..-3]).auth(*args[-2..-1])
      end

      # Shortcut to {ClientExample#example}
      def example(*args)
        new(*args[0..-2]).example(args.last)
      end

      # @return [Array<ClientExample>] sorted array of classes
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

    def init; end

    def auth(method, desc); end

    def version_url
      File.join(base_url, "v#{version}", '/')
    end

    protected

    # @param password [Boolean] include password parameter
    # @return [Hash<String, String>] parameter => example value
    def auth_token_credentials(desc, password: true)
      passwords = %i[password pass passwd]
      params = desc[:resources][:token][:actions]['request'][:input][:parameters].keys - %i[lifetime interval]

      unless password
        params.reject! { |param| passwords.include?(param) }
      end

      Hash[params.map do |param|
        value =
          if passwords.include?(param)
            'secret'
          else
            param
          end

        [param, value]
      end]
    end
  end
end
