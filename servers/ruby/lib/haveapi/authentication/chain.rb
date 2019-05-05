module HaveAPI::Authentication
  # Authentication chain.
  # At every request, #authenticate is called to authenticate user.
  class Chain
    def initialize(server)
      @server = server
      @chain = {}
      @instances = {}
    end

    def setup(versions)
      versions.each do |v|
        @instances[v] ||= []

        @chain[v] && @chain[v].each { |p| register_provider(v, p) }
      end

      if @chain[:all]
        @chain[:all].each do |p|
          @instances.each_key { |v| register_provider(v, p) }
        end
      end

      # @chain.each do |p|
      #   @instances << p.new(@server)
      #
      #   parts = p.to_s.split('::')
      #   mod = Kernel.const_get((parts[0..-2] << 'Resources').join('::'))
      #
      #   @server.add_module(mod, prefix: parts[-2].tableize) if mod
      # end
    end

    # Iterate through authentication providers registered for version +v+
    # until authentication is successful or the end is reached and user
    # is not authenticated.
    # Authentication provider can deny the user access by calling Base#deny.
    def authenticate(v, *args)
      catch(:return) do
        return unless @instances[v]

        @instances[v].each do |provider|
          u = provider.authenticate(*args)
          return u if u
        end
      end

      nil
    end

    def describe(context)
      ret = {}

      return ret unless @instances[context.version]

      @instances[context.version].each do |provider|
        ret[provider.name] = provider.describe

        if provider.resource_module
          ret[provider.name][:resources] = {}

          @server.routes[context.version][:authentication][provider.name][:resources].each do |r, children|
            ret[provider.name][:resources][r.resource_name.underscore.to_sym] = r.describe(children, context)
          end
        end
      end

      ret
    end

    # Return provider list for version +v+.
    # Used for registering providers to specific version, e.g.
    #   api.auth_chain[1] << MyAuthProvider
    def [](v)
      @chain[v] ||= []
      @chain[v]
    end

    # Register authentication +provider+ for all available API versions.
    # +provider+ may also be an Array of providers.
    def <<(provider)
      @chain[:all] ||= []

      if provider.is_a?(Array)
        provider.each { |p| @chain[:all] << p }
      else
        @chain[:all] << provider
      end

      self
    end

    def empty?
      @chain.empty?
    end

    protected
    def register_provider(v, p)
      instance = p.new(@server, v)
      @instances[v] << instance

      if resource_module = instance.resource_module
        @server.add_auth_module(
          v,
          instance.name,
          resource_module,
          prefix: instance.name.to_s,
        )
      end
    end
  end
end
