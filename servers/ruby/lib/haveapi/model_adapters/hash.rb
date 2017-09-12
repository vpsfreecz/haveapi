module HaveAPI::ModelAdapters
  # Simple hash adapter. Model is just a hash of parameters
  # and their values.
  class Hash < ::HaveAPI::ModelAdapter
    register

    def self.handle?(layout, klass)
      klass.is_a?(::Hash)
    end

    class Input < ::HaveAPI::ModelAdapter::Input
      def self.clean(model, raw)
        raw
      end
    end

    class Output < ::HaveAPI::ModelAdapter::Output
      def has_param?(name)
        @object.has_key?(name)
      end

      def [](name)
        @object[name]
      end
    end
  end
end
