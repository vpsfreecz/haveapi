module HaveAPI::CLI
  class Command
    class << self
      attr_reader :resource, :action

      def cmd(resource, action = nil)
        @resource = resource.is_a?(::Array) ? resource : [resource]
        @resource.map! { |v| v.to_s }
        @action = action && action.to_s

        Cli.register_command(self)
      end

      def args(v = nil)
        if v
          @args = v

        else
          @args
        end
      end

      def desc(v = nil)
        if v
          @desc = v

        else
          @desc
        end
      end

      def handle?(resource, action)
        resource == @resource && action == @action
      end
    end

    attr_reader :global_opts

    def initialize(opts, client)
      @global_opts = opts
      @api = client
    end

    def options(opts)

    end

    def exec(args)
      raise NotImplementedError
    end
  end
end
