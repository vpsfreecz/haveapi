require 'pp'

class HaveAPI::Client::Client
  attr_reader :resources

  def initialize(url, v=nil)
    @version = v
    @api = HaveAPI::Client::Communicator.new(url, v)
    @api.identity = 'haveapi-client'

    setup_api(@api.describe_api)
  end

  # See Communicator#authenticate.
  def authenticate(*args)
    @api.authenticate(*args)
  end

  private
  def setup_api(description)
    v = @version || description[:default_version]

    @resources = {}

    description[:versions][v.to_s.to_sym][:resources].each do |name, desc|
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
  end
end
