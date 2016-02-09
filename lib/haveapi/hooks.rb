module HaveAPI
  # All registered hooks and connected endpoints are stored
  # in this module.
  #
  # It supports connecting to both class and instance level hooks.
  # Instance level hooks inherit all class registered hooks, but
  # it is possible to connect to a specific instance and not for
  # all instances of a class.
  #
  # Hook definition contains additional information for as a documentation:
  # description, context, arguments, return value.
  #
  # Every hook can have multiple listeners. They are invoked in the order of
  # registration. Instance-level listeners first, then class-level. Hooks are
  # chained using the block's first argument and return value. The first block
  # to be executed gets the initial value, may make changes and returns it.
  # The next block gets the return value of the previous block as its first
  # argument, may make changes and returns it. Return value of the last block
  # is returned to the caller of the hook.
  #
  # === \Usage
  # ==== \Register hooks
  #   class MyClass
  #     include Hookable
  #
  #     has_hook :myhook,
  #              desc: 'Called when I want to',
  #              context: 'current',
  #              args: {
  #                  a: 'integer',
  #                  b: 'integer',
  #                  c: 'integer',
  #              }
  #   end
  #
  # Not that the additional information is just optional. A list of defined
  # hooks and their description is a part of the reference documentation
  # generated by yard.
  #
  # ==== \Class level hooks
  #   # Connect hook
  #   MyClass.connect_hook(:myhook) do |ret, a, b, c|
  #     # a = 1, b = 2, c = 3
  #     puts "Class hook!"
  #     ret
  #   end
  #
  #   # Call hooks
  #   MyClass.call_hooks(:myhook, args: [1, 2, 3])
  #
  # ==== \Instance level hooks
  #   # Create an instance of MyClass
  #   my = MyClass.new
  #
  #   # Connect hook
  #   my.connect_hook(:myhook) do |ret, a, b, c|
  #     # a = 1, b = 2, c = 3
  #     puts "Instance hook!"
  #     ret
  #   end
  #
  #   # Call instance hooks
  #   my.call_instance_hooks_for(:myhook, args: [1, 2, 3])
  #   # Call class hooks
  #   my.call_class_hooks_for(:myhook, args: [1, 2, 3])
  #   # Call both instance and class hooks at once
  #   my.call_hooks_for(:myhook, args: [1, 2, 3])
  #
  # ==== \Chaining
  #   5.times do |i|
  #     MyClass.connect_hook(:myhook) do |ret, a, b, c|
  #       ret[:counter] += i
  #       ret
  #     end
  #   end
  #
  #   p MyClass.call_hooks(:myhook, args: [1, 2, 3], initial: {counter: 0})
  #   => {:counter=>5}
  module Hooks
    INSTANCE_VARIABLE = '@_haveapi_hooks'

    # Register a hook defined by +klass+ with +name+.
    # +klass+ is an instance of Class, that is class name, not it's instance.
    # +opts+ is a hash and can have following keys:
    #   - desc - why this hook exists, when it's called
    #   - context - the context in which given blocks are called
    #   - args - hash of block arguments
    #   - initial - hash of initial values
    #   - ret - hash of return values
    def self.register_hook(klass, name, opts = {})
      classified = hook_classify(klass)
      opts[:listeners] = []

      @hooks ||= {}
      @hooks[classified] ||= {}
      @hooks[classified][name] = opts
    end

    def self.hooks
      @hooks
    end

    # Connect class hook defined in +klass+ with +name+ to +block+.
    # +klass+ is a class name.
    def self.connect_hook(klass, name, &block)
      @hooks[hook_classify(klass)][name][:listeners] << block
    end

    # Connect instance hook from instance +klass+ with +name+ to +block+.
    def self.connect_instance_hook(instance, name, &block)
      hooks = instance.instance_variable_get(INSTANCE_VARIABLE)

      unless hooks
        hooks = {}
        instance.instance_variable_set(INSTANCE_VARIABLE, hooks)
      end

      hooks[name] ||= {listeners: []}
      hooks[name][:listeners] << block
    end

    # Call all blocks that are connected to hook in +klass+ with +name+.
    # +klass+ may be a class name or an object instance.
    # If +where+ is set, the blocks are executed in it with instance_exec.
    # +args+ is an array of arguments given to all blocks. The first argument
    # to all block is always a return value from previous block or +initial+,
    # which defaults to an empty hash.
    #
    # Blocks are executed one by one in the order they were connected.
    # Blocks must return a hash, that is then passed to the next block
    # and the return value from the last block is returned to the caller.
    #
    # A block may decide that no further blocks should be executed.
    # In such a case it calls Hooks.stop with the return value. It is then
    # returned to the caller immediately.
    #
    # @param klass [Class instance, instance]
    # @param name [Symbol] hook name
    # @param where [Class instance] class in whose context hooks are executed
    # @param args [Array] an array of arguments passed to hooks
    # @param initial [Hash] initial return value
    # @param instance [Boolean] call instance hooks or not; nil means auto-detect
    def self.call_for(
        klass,
        name,
        where = nil,
        args: [],
        initial: {},
        instance: nil
    )
      classified = hook_classify(klass)

      if (instance.nil? && !classified.is_a?(Class)) || instance
        all_hooks = klass.instance_variable_get(INSTANCE_VARIABLE)

      else
        all_hooks = @hooks[classified]
      end

      catch(:stop) do
        return initial unless all_hooks
        return initial unless all_hooks[name]
        hooks = all_hooks[name][:listeners]
        return initial unless hooks

        hooks.each do |hook|
          if where
            ret = where.instance_exec(initial, *args, &hook)

          else
            ret = hook.call(initial, *args)
          end

          initial.update(ret) if ret
        end

        initial
      end
    end

    def self.hook_classify(klass)
      klass.is_a?(String) ? Object.const_get(klass) : klass
    end

    def self.stop(ret)
      throw(ret)
    end
  end

  # Classes that define hooks must include this module.
  module Hookable
    module ClassMethods
      # Register a hook named +name+.
      def has_hook(name, opts = {})
        Hooks.register_hook(self.to_s, name, opts)
      end

      # Connect +block+ to registered hook with +name+.
      def connect_hook(name, &block)
        Hooks.connect_hook(self.to_s, name, &block)
      end

      # Call all hooks for +name+. see Hooks.call_for.
      def call_hooks(*args)
        Hooks.call_for(self.to_s, *args)
      end
    end

    module InstanceMethods
      # Call all instance and class hooks.
      def call_hooks_for(*args)
        ret = call_instance_hooks_for(*args)

        if args.last.is_a?(::Hash)
          args.last.update(initial: ret)
          call_class_hooks_for(*args)
        else
          call_class_hooks_for(*args, initial: ret)
        end
      end

      # Call only instance hooks.
      def call_instance_hooks_for(name, where = nil, args: [], initial: {})
        Hooks.call_for(self, name, where, args: args, initial: initial)
      end

      # Call only class hooks.
      def call_class_hooks_for(name, where  = nil, args: [], initial: {})
        Hooks.call_for(self.class, name, where, args: args, initial: initial)
      end

      # Call hooks for different +klass+.
      def call_hooks_as_for(klass, *args)
        ret = call_instance_hooks_as_for(klass, *args)
        call_class_hooks_as_for(klass.class, *args, initial: ret)
      end

      # Call only instance hooks for different +klass+.
      def call_instance_hooks_as_for(klass, *args)
        Hooks.call_for(klass, *args)
      end

      # Call only class hooks for different +klass+.
      def call_class_hooks_as_for(klass, *args)
        Hooks.call_for(klass, *args)
      end

      # Connect instance level hook +name+ to +block+.
      def connect_hook(name, &block)
        Hooks.connect_instance_hook(self, name, &block)
      end
    end

    def self.included(base)
      base.send(:extend, ClassMethods)
      base.send(:include, InstanceMethods)
    end
  end
end
