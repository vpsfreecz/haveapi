module HaveAPI
  module Hooks
    def self.register_hook(klass, name)
      classified = hook_classify(klass)

      @hooks ||= {}
      @hooks[classified] ||= {}
      @hooks[classified][name] = []
    end

    def self.connect_hook(klass, name, &block)
      @hooks[hook_classify(klass)][name] << block
    end

    def self.connect_instance_hook(klass, name, &block)
      unless @hooks[klass]
        @hooks[klass] = {}

        @hooks[klass.class].each do |k, v|
          @hooks[klass][k] = v
        end
      end

      @hooks[klass][name] << block
    end

    def self.call_for(klass, name, where = nil, args: [], initial: {})
      classified = hook_classify(klass)

      catch(:stop) do
        return initial unless @hooks[classified]
        hooks = @hooks[classified][name]
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

    def self.stop
      throw(true)
    end
  end

  module Hookable
    module ClassMethods
      def has_hook(name)
        Hooks.register_hook(self.to_s, name)
      end

      def connect_hook(name, &block)
        Hooks.connect_hook(self.to_s, name, &block)
      end

      def call_hooks(*args)
        Hooks.call_for(self.to_s, *args)
      end
    end

    module InstanceMethods
      def call_hooks_for(*args)
        ret = call_instance_hooks_for(*args)
        call_class_hooks_for(*args, initial: ret)
      end

      def call_instance_hooks_for(name, where = nil, args: [], initial: {})
        Hooks.call_for(self, name, where, args: args, initial: initial)
      end

      def call_class_hooks_for(name, where  = nil, args: [], initial: {})
        Hooks.call_for(self.class, name, where, args: args, initial: initial)
      end

      def call_hooks_as_for(klass, *args)
        ret = call_instance_hooks_as_for(klass, *args)
        call_class_hooks_as_for(klass.class, *args, initial: ret)
      end

      def call_instance_hooks_as_for(klass, *args)
        Hooks.call_for(klass, *args)
      end

      def call_class_hooks_as_for(klass, *args)
        Hooks.call_for(klass, *args)
      end

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
