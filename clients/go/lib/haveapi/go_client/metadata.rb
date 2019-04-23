module HaveAPI::GoClient
  class Metadata
    class Type
      # @return [InputOutput, nil]
      attr_reader :input

      # @return [InputOutput, nil]
      attr_reader :output

      def initialize(action, type, desc)
        @input = desc[:input] && InputOutput.new(
          action,
          :input,
          desc[:input],
          prefix: "Meta#{type.to_s.capitalize}"
        )
        @output = desc[:output] && InputOutput.new(
          action,
          :output,
          desc[:output],
          prefix: "Meta#{type.to_s.capitalize}"
        )
      end

      def resolve_associations
        input && input.resolve_associations
        output && output.resolve_associations
      end
    end

    # @return [Type, nil]
    attr_reader :global

    # @return [Type, nil]
    attr_reader :object

    def initialize(action, desc)
      @global = desc[:global] && Type.new(action, :global, desc[:global])
      @object = desc[:object] && Type.new(action, :object, desc[:object])
    end

    def resolve_associations
      global && global.resolve_associations
      object && object.resolve_associations
    end
  end
end
