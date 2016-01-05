require 'pp'

# HaveAPI client interface.
class HaveAPI::Client::Client
  attr_reader :resources

  # Create an instance of client.
  # The client by default uses the default version of the API.
  # API is asked for description only when needed or by calling #setup.
  # +identity+ is sent in each request to the API in User-Agent header.
  def initialize(url, v = nil, identity: 'haveapi-client')
    @setup = false
    @version = v
    @api = HaveAPI::Client::Communicator.new(url, v)
    @api.identity = identity
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
  def authenticate(*args)
    @api.authenticate(*args)
  end

  # Get uthentication provider
  # @return [HaveAPI::Client::Authentication::Base] if authenticated
  # @return [nil] if not authenticated
  def auth
    @api.auth
  end

  # Initialize the client if it is not yet initialized and call the resource
  # if it exists.
  def method_missing(symbol, *args)
    return super(symbol, *args) if @setup

    setup_api

    if @resources.include?(symbol)
      method(symbol).call(*args)

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
