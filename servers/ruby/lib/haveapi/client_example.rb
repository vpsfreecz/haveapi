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
    SIMPLE_DETAIL_LEVELS = [:simple].freeze
    DEFAULT_DETAIL_LEVELS = %i[simple thorough].freeze

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

      def detail_levels(*values)
        @detail_levels = validated_detail_levels(values) unless values.empty?
        return @detail_levels if instance_variable_defined?(:@detail_levels)

        superclass.respond_to?(:detail_levels) ? superclass.detail_levels : DEFAULT_DETAIL_LEVELS
      end

      # Custom renderers retain their declaration, including for limitations.
      # Built-ins refine this using the already-rendered Simple result.
      def detail_levels_for(_kind, context:, result:, auth_method: nil, auth_description: nil)
        detail_levels
      end

      # Older, explicitly pinned generator adapters only provide resolve/render.
      # Their unknown detail semantics retain this wrapper's declaration.
      def adapter_detail_levels_for(adapter:, kind:, context:, result:, mode:, auth_method: nil, auth_description: nil)
        return detail_levels unless adapter.respond_to?(:detail_levels_for)

        validated_detail_levels(adapter.detail_levels_for(kind:, context:, result:, mode:, auth_method:, auth_description:))
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

      private

      def validated_detail_levels(values)
        unless [SIMPLE_DETAIL_LEVELS, DEFAULT_DETAIL_LEVELS].include?(values)
          raise ArgumentError, 'Example detail levels must be :simple or :simple, :thorough'
        end

        values.frozen? ? values : values.dup.freeze
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

    class UnsupportedAuthentication < StandardError; end

    def auth_field(value, name, default = nil)
      return default unless value.is_a?(Hash)

      value.fetch(name) { value.fetch(name.to_s, default) }
    end

    def auth_token_actions(description)
      token = auth_field(auth_field(description, :resources, {}), :token, {})
      auth_field(token, :actions, {})
    end

    def auth_token_parameters(description, action = :request)
      info = auth_field(auth_token_actions(description), action, {})
      input = auth_field(info, :input, {})
      unless [nil, :hash, 'hash', :object, 'object'].include?(auth_field(input, :layout))
        raise UnsupportedAuthentication, 'This token example requires object input.'
      end

      auth_field(input, :parameters, {})
    end

    # Only advertised machine types/finite constraints supply public literals.
    # Defaults, prose and current-user data are deliberately not consulted.
    def auth_literal(name, parameter, excluding: [])
      type = auth_field(parameter, :type)
      value = case type
              when 'String', 'Text' then %w[password pass passwd].include?(name.to_s) ? 'secret' : name.to_s
              when 'Integer', 'Resource' then 1
              when 'Float' then 1.0
              when 'Boolean' then excluding.include?(false)
              when 'Datetime' then '2026-01-01T00:00:00Z'
              when 'Custom' then {}
              else raise UnsupportedAuthentication, 'This token example has an unsupported input type.'
              end
      validators = auth_field(parameter, :validators, {})
      inclusion = auth_field(auth_field(validators, :include, {}), :values)
      values = inclusion.is_a?(Hash) ? inclusion.keys : inclusion
      acceptance = auth_field(validators, :accept)
      if acceptance.is_a?(Hash) && (acceptance.has_key?(:value) || acceptance.has_key?('value'))
        value = auth_field(acceptance, :value)
      elsif values.is_a?(Array)
        raise UnsupportedAuthentication, 'This token example has no advertised input choice.' if values.empty?

        value = values.find { |choice| !excluding.include?(choice) }
      end
      value = 'fixed' if name.to_s == 'lifetime'
      value = value.to_s if value.is_a?(Symbol) && %w[String Text].include?(type)
      if excluding.include?(value)
        raise UnsupportedAuthentication, 'This token client cannot send the advertised login input value.'
      end

      compatible = case type
                   when 'String', 'Text', 'Datetime' then value.is_a?(String)
                   when 'Integer' then value.is_a?(Integer)
                   when 'Resource' then value.is_a?(Integer) || value.is_a?(String)
                   when 'Float' then value.is_a?(Numeric) && value.finite?
                   when 'Boolean' then [true, false].include?(value)
                   when 'Custom' then value.is_a?(Hash) || value.is_a?(Array) || value.is_a?(String) || value.is_a?(Numeric) || [true, false, nil].include?(value)
                   end
      compatible &&= values.map { |item| item.is_a?(Symbol) ? item.to_s : item }.include?(value) if values.is_a?(Array)
      compatible &&= value == auth_field(acceptance, :value) if acceptance.is_a?(Hash)
      raise UnsupportedAuthentication, 'This token example cannot represent its advertised input choice.' unless compatible

      value
    end

    def auth_login_literal(_name, _parameter, value)
      value
    end

    # @param password [Boolean] include an interactive password parameter
    def auth_token_credentials(description, password: true, action: :request)
      auth_token_parameters(description, action).each_with_object({}) do |(name, parameter), input|
        next if name.to_s == 'token' || (!password && %w[password pass passwd].include?(name.to_s))
        next if name.to_s == 'interval' && !auth_field(parameter, :required)

        begin
          value = auth_literal(name, parameter)
        rescue UnsupportedAuthentication
          raise if auth_field(parameter, :required) || name.to_s == 'lifetime'

          next
        end
        input[name.to_s] = action.to_s == 'request' ? auth_login_literal(name, parameter, value) : value
      end
    end

    def auth_token_continuations(description)
      auth_token_actions(description).each_with_object({}) do |(name, _action), result|
        next if %w[request renew revoke].include?(name.to_s)

        result[name.to_s] = auth_token_credentials(description, action: name)
      end
    end
  end
end
