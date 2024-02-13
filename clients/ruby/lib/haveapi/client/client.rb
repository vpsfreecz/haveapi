require 'pp'

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
  def initialize(url, opts = {})
    @setup = false
    @opts = opts
    @version = @opts[:version]
    @opts[:identity] ||= 'haveapi-client'
    @opts[:block] = true if @opts[:block].nil?

    if @opts[:communicator]
      @api = @opts[:communicator]

    else
      @api = HaveAPI::Client::Communicator.new(url, @version)
      @api.identity = @opts[:identity]
    end
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
  def authenticate(auth_method, **options, &)
    @api.authenticate(auth_method, options, &)
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
  end

  # @return [Hash] client options
  def opts(*keys)
    keys.empty? ? @opts.clone : @opts.select { |k, _| keys.include?(k) }
  end

  # @return [HaveAPI::Client::Communicator]
  def communicator
    @api
  end

  # Initialize the client if it is not yet initialized and call the resource
  # if it exists.
  def method_missing(symbol, *)
    return super(symbol, *args) if @setup

    setup_api

    if @resources.include?(symbol)
      method(symbol).call(*)

    else
      super(symbol, *args)
    end
  end

  private

  # Get the description from the API and setup resource methods.
  def setup_api
    @description = @api.describe_api(@version)
    @resources = {}

    @description[:resources].each do |name, desc|
      r = HaveAPI::Client::Resource.new(self, @api, name)
      r.setup(desc)

      define_singleton_method(name) do |*args|
        tmp = r.dup
        tmp.prepared_args = args
        tmp.setup_from_clone(r)
        tmp
      end

      @resources[name] = r
    end

    @setup = true
  end
end
