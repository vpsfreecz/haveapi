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

      def clone
        m = self.class.new
        m.action = @action
        m.instance_variable_set(:@input, @input && @input.clone)
        m.instance_variable_set(:@output, @output && @output.clone)
        m
      end

      def input(layout = :hash, &block)
        if block
          @input ||= Params.new(:input, @action)
          @input.action = @action
          @input.layout = layout
          @input.namespace = false
          @input.add_block(block)
        else
          @input
        end
      end

      def output(layout = :hash, &block)
        if block
          @output ||= Params.new(:output, @action)
          @output.action = @action
          @output.layout = layout
          @output.namespace = false
          @output.add_block(block)
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
