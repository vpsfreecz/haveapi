module VpsAdmin
  module API
    class Action
      def initialize(spec)
        @spec = spec
      end

      def input
        @spec[:input]
      end

      def output
        @spec[:output]
      end

      def url
        @spec[:url]
      end

      def http_method
        @spec[:method]
      end
    end
  end
end
