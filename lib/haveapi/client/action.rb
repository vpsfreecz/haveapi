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
      params = Params.new(self, data)
      
      unless params.valid?
        raise ValidationError.new(self, params.errors)
      end

      ret = @api.call(self, params.to_api)
      @prepared_url = nil
      @prepared_help = nil
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

    def url
      @spec[:url]
    end

    def help
      @spec[:help]
    end

    # Url with resolved parameters.
    def prepared_url
      @prepared_url || @spec[:url]
    end

    def prepared_help
      @prepared_help || @spec[:help]
    end

    def http_method
      @spec[:method]
    end

    def unresolved_args?
      prepared_url =~ /:[a-zA-Z\-_]+/
    end

    def provide_args(*args)
      apply_args(args)
    end

    def provide_url(url, help)
      @prepared_url = url
      @prepared_help = help
    end

    def update_description(spec)
      @spec = spec
    end
  
    # Block until the action is completed or timeout occurs. If the block is given,
    # it is regularly called with the action's state.
    # @param interval [Float] how often should the action state be checked
    # @param timeout [Integer] timeout in seconds
    # @param desc [Hash] has to be provided if action.client is nil
    # @yieldparam state [Hash]
    def wait_for_completion(id, interval: 3, timeout: nil, desc: nil)
      if @client
        resource = @client.action_state

      else
        resource = HaveAPI::Client::Resource.new(@client, @api, :action_state)
        resource.setup(desc)
      end

      res = nil
      t = Time.now if timeout

      loop do
        res = resource.poll(id, timeout: interval)

        yield(res.response) if block_given?
        break if res.response[:finished]
        return nil if timeout && (Time.now - t) >= timeout
      end

      res.response[:status]
    end

    def cancel(id, desc: nil)
      if @client
        resource = @client.action_state

      else
        resource = HaveAPI::Client::Resource.new(@client, @api, :action_state)
        resource.setup(desc)
      end
      
      resource.cancel(id)
    end

    private
    def apply_args(args)
      @prepared_url ||= @spec[:url].dup
      @prepared_help ||= @spec[:help].dup

      args.each do |arg|
        @prepared_url.sub!(/:[a-zA-Z\-_]+/, arg.to_s)
        @prepared_help.sub!(/:[a-zA-Z\-_]+/, arg.to_s)
      end
    end
  end
end
