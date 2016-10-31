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
