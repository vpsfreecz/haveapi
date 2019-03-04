require 'haveapi/common'

module HaveAPI
  class Resource < Common
    obj_type :resource
    has_attr :version
    has_attr :desc
    has_attr :model
    has_attr :route
    has_attr :auth, true
    has_attr :singular, false

    def self.inherited(subclass)
      subclass.instance_variable_set(:@obj_type, obj_type)
    end

    def self.params(name, &block)
      if block
        @params ||= {}
        @params[name] = block
      else
        @params[name]
      end
    end

    def self.actions
      constants.select do |c|
        obj = const_get(c)

        if obj.respond_to?(:obj_type) && obj.obj_type == :action
          yield obj
        end
      end
    end

    def self.resources
      constants.select do |c|
        obj = const_get(c)

        begin
          if obj.obj_type == :resource
            yield obj
          end

        rescue NoMethodError
          next
        end
      end
    end

    def self.resource_name
      ret = self.to_s.demodulize

      singular ? ret.singularize.underscore : ret.tableize
    end

    def self.routes(prefix='/')
      ret = []
      prefix = "#{prefix}#{@route || resource_name}/"

      actions do |a|
        # Call used_by for selected model adapters. It is safe to do
        # only when all classes are loaded.
        a.initialize

        ret << Route.new(a.build_route(prefix).chomp('/'), a)
      end

      resources do |r|
        ret << {r => r.routes(prefix)}
      end

      ret
    end

    def self.describe(hash, context)
      ret = {description: self.desc, actions: {}, resources: {}}

      context.resource = self

      hash[:actions].each do |action, url|
        context.action = action
        context.url = url

        a_name = action.to_s.demodulize.underscore

        a_desc = action.describe(context)

        ret[:actions][a_name] = a_desc if a_desc
      end

      hash[:resources].each do |resource, children|
        ret[:resources][resource.to_s.demodulize.underscore] = resource.describe(children, context)
      end

      ret
    end

    def self.define_resource(name, superclass: Resource, &block)
      return false if const_defined?(name)

      cls = Class.new(superclass)
      const_set(name, cls)
      cls.class_exec(&block) if block
      cls
    end

    def self.define_action(name, superclass: Action, &block)
      return false if const_defined?(name)

      cls = Class.new(superclass)
      const_set(name, cls)
      superclass.delayed_inherited(cls)
      cls.class_exec(&block)
    end
  end
end
