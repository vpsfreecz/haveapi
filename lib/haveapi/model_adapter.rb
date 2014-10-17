module HaveAPI
  # Model adapters are used to automate handling of action
  # input/output.
  #
  # Adapters are chosen based on the +model+ set on a HaveAPI::Resource.
  # If no +model+ is specified, ModelAdapters::Hash is used as a default
  # adapter.
  #
  # All model adapters are based on this class.
  class ModelAdapter
    class << self
      attr_accessor :adapters

      # Every model adapter must register itself using this method.
      def register
        ModelAdapter.adapters ||= []
        ModelAdapter.adapters << Kernel.const_get(self.to_s)
      end

      # Returns an adapter suitable for +layout+ and +obj+.
      # Adapters are iterated over and the first to return true to handle?()
      # is returned.
      def for(layout, obj)
        return ModelAdapters::Hash if !obj || %i(hash hash_list).include?(layout)
        adapter = @adapters.detect { |adapter| adapter.handle?(layout, obj) }
        adapter || ModelAdapters::Hash
      end

      # Shortcut to Input::clean.
      def input_clean(*args)
        self::Input.clean(*args)
      end

      # Shortcut to get an instance of Input model adapter.
      def input(*args)
        self::Input.new(*args)
      end

      # Shortcut to get an instance of Output model adapter.
      def output(*args)
        self::Output.new(*args)
      end

      # Override this method to load validators from +model+
      # to +params+.
      def load_validators(model, params)

      end
    end

    # Subclass this class in your adapter and reimplement
    # necessary methods.
    class Input
      def initialize(input)
        @input = input
      end

      # Return true if input parameters contain parameter
      # with +name+.
      def has_param?(name)
        @input.has_key?(name)
      end

      # Return parameter with +name+.
      def [](name)
        @input[name]
      end

      # Return model instance from a raw input resource parameter.
      def self.clean(raw)

      end
    end

    # Subclass this class in your adapter and reimplement
    # necessary methods.
    class Output
      def initialize(context, obj)
        @context = context
        @object = obj
      end

      # Return true if input parameters contain parameter
      # with +name+.
      def has_param?(name)

      end

      # Return a parameter in an appropriate format to be sent to a client.
      def [](name)

      end
    end
  end
end
