class VpsAdmin::API::Resource
  attr_reader :actions, :resources, :name
  attr_accessor :prepared_args

  def initialize(api, name)
    @api = api
    @name = name
    @prepared_args = []
  end

  def setup(description)
    @actions = {}
    @resources = {}

    description[:actions].each do |name, desc|
      action = VpsAdmin::API::Action.new(@api, name, desc, [])
      define_action(action)
      @actions[name] = action
    end

    description[:resources].each do |name, desc|
      r = VpsAdmin::API::Resource.new(@api, name)
      r.setup(desc)
      define_resource(r)
      @resources[name] = r
    end
  end

  def setup_from_clone(original)
    original.actions.each_value do |action|
      define_action(action)
    end

    original.resources.each_value do |resource|
      define_resource(resource)
    end
  end

  private
  def define_action(action)
    define_singleton_method(action.name) do |*args|
      all_args = @prepared_args + args

      if action.unresolved_args?
        all_args.delete_if do |arg|
          break unless action.unresolved_args?

          action.provide_args(arg)
          true
        end

        if action.unresolved_args?
          raise ArgumentError.new('One or more object ids missing')
        end
      end

      all_args << {} if all_args.empty?

      VpsAdmin::API::Response.new(action, action.execute(*all_args))
    end
  end

  def define_resource(resource)
    define_singleton_method(resource.name) do |*args|
      tmp = resource.dup
      tmp.prepared_args = @prepared_args + args
      tmp.setup_from_clone(resource)
      tmp
    end
  end
end
