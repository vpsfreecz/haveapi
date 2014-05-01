module VpsAdmin
  module API
    class Action
      def initialize(api, spec, args)
        @api = api
        @spec = spec

        apply_args(args)
      end

      def execute(*args)
        @api.call(self, *args)
      end

      def input
        @spec[:input]
      end

      def output
        @spec[:output]
      end

      def layout
        @spec[:output][:layout]
      end

      def structure
        @spec[:output][:format]
      end

      def params
        @spec[:output][:parameters]
      end

      def url
        @spec[:url]
      end

      def http_method
        @spec[:method]
      end

      private
        def apply_args(args)
          args.each do |arg|
            @spec[:url].sub!(/:[a-zA-Z\-_]+/, arg)
          end
        end
    end
  end
end
