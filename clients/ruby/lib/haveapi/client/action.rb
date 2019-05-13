module HaveAPI::Client
  class Action
    attr_reader :client, :api, :name
    attr_accessor :resource_path

    def initialize(client, api, name, spec, args)
      @client = client
      @api = api
      @name = name
      @spec = spec

      apply_args(args)
    end

    def execute(data, *_)
      args = [self]

      if input
        params = Params.new(self, data)

        unless params.valid?
          raise ValidationError.new(self, params.errors)
        end

        args << params.to_api << {}
      end

      ret = @api.call(*args)
      reset
      ret
    end

    def name
      @name
    end

    def auth?
      @spec[:auth]
    end

    def blocking?
      @spec[:blocking]
    end

    def aliases(include_name = false)
      if include_name
        [@name] + @spec[:aliases]
      else
        @spec[:aliases]
      end
    end

    def description
      @spec[:description]
    end

    def input
      @spec[:input]
    end

    def output
      @spec[:output]
    end

    def input_layout
      @spec[:input][:layout].to_sym
    end

    def output_layout
      @spec[:output][:layout].to_sym
    end

    def structure
      @spec[:output][:format]
    end

    def namespace(src)
      @spec[src][:namespace]
    end

    def examples
      @spec[:examples]
    end

    def input_params
      @spec[:input][:parameters]
    end

    def params
      @spec[:output][:parameters]
    end

    def param_description(dir, name)
      @spec[dir][:parameters][name]
    end

    def meta(scope)
      @spec[:meta][scope]
    end

    def path
      @spec[:path]
    end

    def help
      @spec[:help]
    end

    # Url with resolved parameters.
    def prepared_path
      @prepared_path || @spec[:path]
    end

    def prepared_help
      @prepared_help || @spec[:help]
    end

    def http_method
      @spec[:method]
    end

    def unresolved_args?
      prepared_path =~ /:[a-zA-Z\-_]+/
    end

    def provide_args(*args)
      apply_args(args)
    end

    def provide_path(path, help)
      @prepared_path = path
      @prepared_help = help
    end

    def reset
      @prepared_path = nil
      @prepared_help = nil
    end

    def update_description(spec)
      @spec = spec
    end

    # Block until the action is completed or timeout occurs. If the block is given,
    # it is regularly called with the action's state.
    # @param interval [Float] how often should the action state be checked
    # @param timeout [Integer] timeout in seconds
    # @yieldparam state [ActionState]
    # @return [Boolean] when the action is finished
    # @return [nil] when timeout occurs
    # @return [Response] if the action was cancelled and the cancel itself isn't blocking
    # @return [Integer] id of cancellation if the action was cancelled, cancel is blocking
    #                   and no cancel block is provided
    def self.wait_for_completion(client, id, interval: 15, update_in: 3, timeout: nil)
      res = client.action_state.show(id)
      state = ActionState.new(res)

      yield(state) if block_given?
      return state.status if state.finished?

      last = {}
      t = Time.now if timeout

      loop do
        res = client.action_state.poll(
            id,
            timeout: interval,
            update_in: update_in,
            status: last[:status],
            current: last[:current],
            total: last[:total],
        )

        state = ActionState.new(res)

        last[:status] = res.response[:status]
        last[:current] = res.response[:current]
        last[:total] = res.response[:total]

        yield(state) if block_given?
        break if state.finished?

        if state.cancel?
          state.stop
          cancel_block = state.cancel_block

          ret = cancel(client, id)

          if ret.is_a?(Response)
            # The cancel is not a blocking operation, return immediately
            raise ActionFailed, ret unless ret.ok?
            return ret
          end

          # Cancel is a blocking operation
          if cancel_block
            return wait_for_completion(
                client,
                ret,
                interval: interval,
                timeout: timeout,
                update_in: update_in,
                &cancel_block
            )
          end

          return ret
        end

        return nil if (timeout && (Time.now - t) >= timeout) || state.stop?
      end

      state.status

    rescue Interrupt => e
      %i(show poll).each do |action|
        client.action_state.actions[action].reset
      end
      raise e
    end

    def self.cancel(client, id)
      res = client.action_state.cancel(id, meta: {block: false})

      if res.ok? && res.action.blocking? && res.meta[:action_state_id]
        res.meta[:action_state_id]

      else
        res
      end
    end

    private
    def apply_args(args)
      @prepared_path ||= @spec[:path].dup
      @prepared_help ||= @spec[:help].dup

      args.each do |arg|
        @prepared_path.sub!(/\{[a-zA-Z\-_]+\}/, arg.to_s)
        @prepared_help.sub!(/\{[a-zA-Z\-_]+\}/, arg.to_s)
      end
    end
  end
end
