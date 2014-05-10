class VpsAdmin::API::Resource
  attr_reader :actions, :resources

  def initialize(api, name)
    @api = api
    @name = name
  end

  def setup(description)
    @actions = {}
    @resources = {}

    description[:actions].each do |name, desc|
      action = VpsAdmin::API::Action.new(@api, desc, [])

      define_singleton_method(name) do |*args|
        if action.unresolved_args?
          args.delete_if do |arg|
            break unless action.unresolved_args?

            action.provide_args(arg)
            true
          end

          if action.unresolved_args?
            raise ArgumentError.new('One or more object ids missing')
          end
        end

        args << {} if args.empty?

        VpsAdmin::API::Response.new(action, action.execute(*args))
      end

      @actions[name] = action
    end

    description[:resources].each do |name, desc|
      r = VpsAdmin::API::Resource.new(@api, name)
      r.setup(desc)

      define_singleton_method(name) do
        r
      end

      @resources[name] = r
    end
  end
end
