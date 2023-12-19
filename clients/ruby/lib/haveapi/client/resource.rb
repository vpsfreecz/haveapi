module HaveAPI::Client
  # An API resource.
  class Resource
    attr_reader :actions, :resources
    attr_accessor :prepared_args

    def initialize(client, api, name)
      @client = client
      @api = api
      @name = name
      @prepared_args = []
      @actions = {}
      @resources = {}
    end

    def inspect
      "#<#{self.class.name} @name=#{@name} @prepared_args=#{@prepared_args} @actions=#{@actions.keys.inspect} @resources=#{@resources.keys.inspect}>"
    end

    def setup(description)
      @description = description

      description[:actions].each do |name, desc|
        action = HaveAPI::Client::Action.new(@client, @api, name, desc, [])
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
      @description = original._description

      original.actions.each do |name, action|
        define_action(action)
        @actions[name] = action
      end

      original.resources.each do |name, resource|
        define_resource(resource)
        @resources[name] = resource
      end
    end

    # Create a new instance of a resource. The created instance
    # is not persistent until ResourceInstance#save is called.
    def new
      ResourceInstance.new(@client, @api, self, action: @actions[:create], persistent: false)
    end

    # Return resource name.
    # Method is prefixed with an underscore to prevent name collision
    # with ResourceInstance attributes.
    def _name
      @name
    end

    # Return resource description.
    # Method is prefixed with an underscore to prevent name collision
    # with ResourceInstance attributes.
    def _description
      @description
    end

    protected
    # Define access/write methods for action +action+.
    def define_action(action)
      action.aliases(true).each do |name|
        next unless define_method?(action, name)

        define_singleton_method(name) do |*args, **kwargs, &block|
          client_opts = @client.opts(:block, :block_interval, :block_timeout)
          all_args = @prepared_args + args

          if action.unresolved_args?
            all_args.delete_if do |arg|
              break unless action.unresolved_args?

              action.provide_args(arg)
              true
            end

            if action.unresolved_args?
              raise ArgumentError, 'one or more object ids missing'
            end
          end

          if all_args.length > 1 || (kwargs.any? && all_args.any?)
            raise ArgumentError, "too many arguments for action #{@name}##{action.name}"
          end

          arg = all_args.shift

          user_params =
            if kwargs.any? && arg
              raise ArgumentError,
                    'pass the input parameters either as a hash or keyword arguments'
            elsif kwargs.any?
              kwargs
            elsif arg
              arg
            end

          if user_params.nil?
            input_params = default_action_input_params(action)

          else
            if user_params.has_key?(:meta)
              meta = user_params[:meta]

              %i(block block_interval block_timeout).each do |p|
                client_opts[p] = meta.delete(p) if meta.has_key?(p)
              end
            end

            input_params = default_action_input_params(action).update(user_params)
          end

          ret = Response.new(action, action.execute(input_params))

          raise ActionFailed.new(ret) unless ret.ok?

          return_value = case action.output && action.output_layout
            when :object
              ResourceInstance.new(@client, @api, self, action: action, response: ret)

            when :object_list
              ResourceInstanceList.new(@client, @api, self, action, ret)

            when :hash, :hash_list
              ret

            else
              ret
          end

          if action.blocking? && client_opts[:block]
            wait_opts = {}

            {
                block_interval: :interval,
                block_timeout: :timeout
            }.each do |k, v|
              wait_opts[v] = client_opts[k] if client_opts.has_key?(k)
            end

            ret.wait_for_completion(**wait_opts) do |state|
              block.call(return_value, state) if block
            end
          end

          return_value
        end
      end
    end

    # Called before defining a method named +name+ that will
    # invoke +action+.
    def define_method?(action, name)
      return false if %i(new).include?(name.to_sym)
      true
    end

    # This method is called when an action is invoked.
    # Override it to return a default hash of parameters to be sent to API.
    # Used for example in ResourceInstance, which returns its instance attributes.
    def default_action_input_params(action)
      {}
    end

    def define_resource(resource)
      define_singleton_method(resource._name) do |*args|
        tmp = resource.dup
        tmp.prepared_args = @prepared_args + args
        tmp.setup_from_clone(resource)
        tmp
      end
    end
  end
end
