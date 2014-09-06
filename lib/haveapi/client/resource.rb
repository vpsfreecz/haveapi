module HaveAPI::Client
  # An API resource.
  class Resource
    attr_reader :actions, :resources, :name
    attr_accessor :prepared_args

    def initialize(client, api, name)
      @client = client
      @api = api
      @name = name
      @prepared_args = []
    end

    def setup(description)
      @actions = {}
      @resources = {}

      description[:actions].each do |name, desc|
        action = HaveAPI::Client::Action.new(@api, name, desc, [])
        define_action(action)
        @actions[name] = action
      end

      description[:resources].each do |name, desc|
        r = HaveAPI::Client::Resource.new(@client, @api, name)
        r.setup(desc)
        define_resource(r)
        @resources[name] = r
      end
    end

    # Copy actions and resources from the +original+ resource
    # and create methods for this instance.
    def setup_from_clone(original)
      original.actions.each_value do |action|
        define_action(action)
      end

      original.resources.each_value do |resource|
        define_resource(resource)
      end
    end

    def inspect
      super
    end

    # Create a new instance of a resource. The created instance
    # is not persistent until ResourceInstance#save is called.
    def new
      ResourceInstance.new(@client, @api, self, action: @actions[:create], persistent: false)
    end

    protected
    # Define access/write methods for action +action+.
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

        if all_args.empty?
          all_args << default_action_input_params(action)

        else
          last = all_args.pop

          all_args << default_action_input_params(action).update(last)
        end

        ret = Response.new(action, action.execute(*all_args))

        raise ActionFailed.new(ret) unless ret.ok?

        case action.output_layout
          when :object
            ResourceInstance.new(@client, @api, self, action: action, response: ret)

          when :object_list
            ResourceInstanceList.new(@client, @api, self, action, ret)

          when :hash, :hash_list
            ret

          else
            ret
        end
      end
    end

    # This method is called when an action is invoked.
    # Override it to return a default hash of parameters to be sent to API.
    # Used for example in ResourceInstance, which returns its instance attributes.
    def default_action_input_params(action)
      {}
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
end
