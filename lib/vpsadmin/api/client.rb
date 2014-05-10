require 'pp'

class VpsAdmin::API::Client
  attr_reader :resources

  def initialize(v=nil)
    @version = v
    @api = VpsAdmin::API::Communicator.new('http://localhost:4567')

    setup_api(@api.describe_api)
  end

  def login(*credentials)
    @api.login(*credentials)
  end

  private
  def setup_api(description)
    v = @version || description[:default_version]

    @resources = {}

    description[:versions][v.to_s.to_sym][:resources].each do |name, desc|
      r = VpsAdmin::API::Resource.new(@api, name)
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
