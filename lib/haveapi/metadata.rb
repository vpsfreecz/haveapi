module HaveAPI
  class Metadata
    def self.namespace
      :_meta
    end

    def self.describe
      {
          namespace: namespace
      }
    end

    class ActionMetadata
      attr_writer :action

      def initialize(action)
        @action = action
      end

      def input(layout = :hash, namespace: nil, &block)
        if block
          @input ||= Params.new(:input, @action)
          @input.layout = layout
          @input.namespace = namespace
          @input.instance_eval(&block)
        else
          @input
        end
      end

      def output(layout = :hash, namespace: nil, &block)
        if block
          @output ||= Params.new(:output, @action)
          @output.layout = layout
          @output.namespace = namespace
          @output.instance_eval(&block)
        else
          @output
        end
      end

      def describe(context)
        {
          input: @input && @input.describe(context),
          output: @output && @output.describe(context)
        }
      end
    end
  end
end
