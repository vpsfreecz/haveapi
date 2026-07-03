# HaveAPI client interface.
class HaveAPI::Client::Client
  attr_reader :resources

  # Create an instance of client.
  # The client by default uses the default version of the API.
  # API is asked for description only when needed or by calling #setup.
  # +identity+ is sent in each request to the API in User-Agent header.
  # @param url [String] API URL
  # @param opts [Hash]
  # @option opts [String] version
  # @option opts [String] identity
  # @option opts [HaveAPI::Client::Communicator] communicator
  # @option opts [Boolean] block
  # @option opts [Integer] block_interval
  # @option opts [Integer] block_timeout
  # @option opts [Boolean] verify_ssl
  # @option opts [String] language value sent in Accept-Language
  # @option opts [String] language_header HTTP header used for language
  def initialize(url, opts = {})
    @setup = false
    @opts = opts
    @version = @opts[:version]
    @opts[:identity] ||= 'haveapi-client'
    @opts[:block] = true if @opts[:block].nil?

    if @opts[:communicator]
      @api = @opts[:communicator]

    else
      @api = HaveAPI::Client::Communicator.new(
        url,
        @version,
        **{
          verify_ssl: opts[:verify_ssl],
          language: opts[:language],
          language_header: opts[:language_header]
        }.compact
      )
      @api.identity = @opts[:identity]
    end

    @api.language = @opts[:language] if @opts.has_key?(:language)
    @api.language_header = @opts[:language_header] if @opts.has_key?(:language_header)
  end

  def inspect
    "#<#{self.class.name} url=#{@api.url} version=#{@opts[:version]}>"
  end

  # Get the description from the API now.
  def setup(v = :_nil)
    @version = v unless v == :_nil
    setup_api
  end

  # Returns a list of API versions.
  # The return value is a hash, e.g.:
  #   {
  #     versions: [1, 2, 3],
  #     default: 3
  #   }
  def versions
    @api.available_versions
  end

  # See Communicator#authenticate.
  def authenticate(auth_method, **options, &block)
    @api.authenticate(auth_method, options, &block)
  end

  # Get uthentication provider
  # @return [HaveAPI::Client::Authentication::Base] if authenticated
  # @return [nil] if not authenticated
  def auth
    @api.auth
  end

  # @see Communicator#compatible?
  def compatible?
    @api.compatible?
  end

  # return [Boolean] true if global blocking mode is enabled
  def blocking?
    @opts[:block]
  end

  # Override selected client options
  # @param opts [Hash] options
  def set_opts(opts)
    @opts.update(opts)
    self.language = opts[:language] if opts.has_key?(:language)
    self.language_header = opts[:language_header] if opts.has_key?(:language_header)
  end

  def language
    @api.language
  end

  def language=(value)
    @api.language = value
  end

  def language_header
    @api.language_header
  end

  def language_header=(value)
    @api.language_header = value
  end

  def client_message(key, **values)
    if @api.respond_to?(:client_message)
      @api.client_message(key, **values)
    else
      lang = @api.language if @api.respond_to?(:language)
      HaveAPI::Client::I18n.t(lang || @opts[:language], key, values)
    end
  end

  # @return [Hash] client options
  def opts(*keys)
    keys.empty? ? @opts.clone : @opts.slice(*keys)
  end

  # @return [HaveAPI::Client::Communicator]
  def communicator
    @api
  end

  # Initialize the client if it is not yet initialized and call the resource
  # if it exists.
  def method_missing(symbol, *args)
    return super if @setup

    setup_api

    if @resource_methods.include?(symbol)
      method(symbol).call(*args)

    else
      super
    end
  end

  def respond_to_missing?(symbol, *_)
    return super if @setup

    setup_api
    @resource_methods.include?(symbol)
  end

  private

  # Get the description from the API and setup resource methods.
  def setup_api
    @description = @api.describe_api(@version)
    old_resource_methods = @resource_methods || {}
    @resources = {}
    @resource_methods = {}

    @description[:resources].each do |name, desc|
      r = HaveAPI::Client::Resource.new(self, @api, name)
      r.setup(desc)
      method_name = name.to_sym

      if old_resource_methods.include?(method_name) || define_resource_method?(name)
        define_singleton_method(name) do |*args|
          tmp = r.dup
          tmp.prepared_args = args
          tmp.setup_from_clone(r)
          tmp
        end

        @resource_methods[method_name] = true
      end

      @resources[name] = r
    end

    @setup = true
  end

  def define_resource_method?(name)
    method_name = name.to_sym

    !singleton_class.public_method_defined?(method_name) &&
      !singleton_class.protected_method_defined?(method_name) &&
      !singleton_class.private_method_defined?(method_name, false) &&
      !self.class.private_method_defined?(method_name, false)
  end
end
