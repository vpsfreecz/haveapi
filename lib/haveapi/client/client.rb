require 'pp'

class HaveAPI::Client::Client
  attr_reader :resources

  def initialize(url, v = nil, identity: 'haveapi-client')
    @setup = false
    @version = v
    @api = HaveAPI::Client::Communicator.new(url, v)
    @api.identity = identity
  end

  def setup(v = :_nil)
    @version = v unless v == :_nil
    setup_api
  end

  def versions
    @api.available_versions
  end

  # See Communicator#authenticate.
  def authenticate(*args)
    @api.authenticate(*args)
  end

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
  def setup_api
    @description = @api.describe_api(@version)
    @resources = {}

    @description[:resources].each do |name, desc|
      r = HaveAPI::Client::Resource.new(@api, name)
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
