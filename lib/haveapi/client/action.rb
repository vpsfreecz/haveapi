module HaveAPI
  module Client
    class Action
      def initialize(api, name, spec, args)
        @api = api
        @name = name
        @spec = spec

        apply_args(args)
      end

      def execute(*args)
        ret = @api.call(self, *args)
        @prepared_url = nil
        ret
      end

      def name
        @name
      end

      def auth?
        @spec[:auth]
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

      def namespace(src)
        @spec[src][:namespace]
      end

      def params
        @spec[:output][:parameters]
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

      def http_method
        @spec[:method]
      end

      def unresolved_args?
        prepared_url =~ /:[a-zA-Z\-_]+/
      end

      def provide_args(*args)
        apply_args(args)
      end

      def update_description(spec)
        @spec = spec
      end

      private
        def apply_args(args)
          @prepared_url ||= @spec[:url].dup

          args.each do |arg|
            @prepared_url.sub!(/:[a-zA-Z\-_]+/, arg.to_s)
          end
        end
    end
  end
end
