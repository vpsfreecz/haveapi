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

      def id(value = nil)
        @id = value.to_s.freeze unless value.nil?
        return @id if @id

        # Preserve the anchors of the retained built-in formats.
        { 'RubyClient' => '0', 'PhpClient' => '2', 'RubyCli' => '3', 'Curl' => '5', 'Http' => '6' }[name.to_s.split('::').last] ||
          name.to_s.gsub('::', '-').downcase
      end

      def available?(_context)
        true
      end

      def language(value = nil)
        @language = value.to_s.freeze unless value.nil?
        @language || id
      end

      def language_label(value = nil)
        @language_label = value.to_s.freeze unless value.nil?
        @language_label || label
      end

      def variant(value = nil)
        @variant = value.to_s.freeze unless value.nil?
        @variant
      end

      def render(kind, context:, auth_method: nil, auth_description: nil)
        arguments = [context.host, context.base_url, context.version]
        arguments.push(context.resource_path, context.resource, context.action_name, context.action) if kind == :example
        renderer = new(*arguments)
        renderer.with_context(context)
        result = case kind
                 when :init then renderer.init
                 when :auth then renderer.auth(auth_method, auth_description)
                 when :example
                   if renderer.respond_to?(:example)
                     renderer.example(context.sample)
                   else
                     [renderer.request(context.sample), renderer.response(context.sample)].compact.join("\n\n")
                   end
                 else raise ArgumentError, "Unknown client example kind: #{kind}"
                 end
        return if result.nil?
        return { status: :code, code: result.dup.freeze }.freeze if result.is_a?(String)

        if result.is_a?(Hash) && result[:status] == :code && result[:code].is_a?(String)
          { status: :code, code: result[:code].dup.freeze }.freeze
        elsif result.is_a?(Hash) && result[:status] == :limitation && result[:reason].is_a?(String)
          { status: :limitation, reason: result[:reason].dup.freeze }.freeze
        else
          raise ArgumentError, 'Invalid client example result'
        end
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
        new(*args[0..-3]).auth(*args[-2..])
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

    attr_reader :resource_path, :resource, :action_name, :action, :host, :base_url, :version, :context

    def initialize(host, base_url, version, *args)
      @host = host
      @base_url = base_url
      @version = version
      @resource_path, @resource, @action_name, @action = args
    end

    def init; end

    def auth(method, desc); end

    def with_context(value)
      @context = value
      self
    end

    def thorough?
      context&.detail == :thorough
    end

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

      params.to_h do |param|
        value =
          if passwords.include?(param)
            'secret'
          else
            param
          end

        [param, value]
      end
    end
  end
end
