module HaveAPI::Authentication
  module Token
    class ActionConfig
      # @param block [Proc]
      # @param opts [Hash]
      # @option opts [Boolean] :input
      # @option opts [Boolean] :handle
      def initialize(block, opts = {})
        @block = block
        @opts = with_defaults(opts)
        update(block)
      end

      # @param block [Proc]
      def update(block)
        instance_exec(&block)
      end

      # Configure input parameters in the context of {HaveAPI::Params}
      def input(&block)
        if block && check!(:input)
          @input = block
        else
          @input
        end
      end

      # Handle the action
      # @yieldparam request [ActionRequest]
      # @yieldparam result [ActionResult]
      # @yieldreturn [ActionResult]
      def handle(&block)
        if block && check!(:handle)
          @handle = block
        else
          @handle
        end
      end

      private
      def check!(name)
        fail "#{name} cannot be configured" unless @opts[name]
        true
      end

      def with_defaults(opts)
        Hash[%i(input handle).map do |v|
          [v, opts.has_key?(v) ? opts[v] : true]
        end]
      end
    end
  end
end
