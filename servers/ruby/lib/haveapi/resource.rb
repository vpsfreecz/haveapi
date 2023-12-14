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

    def self.action_defined(klass)
      @actions ||= []
      @actions << klass
    end

    def self.params(name, &block)
      if block
        @params ||= {}
        @params[name] = block
      else
        @params[name]
      end
    end

    def self.actions(&block)
      (@actions || []).each(&block)
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
      (@resource_name ? @resource_name.to_s : to_s).demodulize
    end

    def self.resource_name=(name)
      @resource_name = name
    end

    def self.rest_name
      singular ? resource_name.singularize.underscore : resource_name.tableize
    end

    def self.routes(prefix='/', resource_path: [])
      ret = []
      prefix = "#{prefix}#{@route || rest_name}/"
      new_resource_path = resource_path + [resource_name.underscore]

      actions do |a|
        # Call used_by for selected model adapters. It is safe to do
        # only when all classes are loaded.
        a.initialize

        ret << Route.new(a.build_route(prefix).chomp('/'), a, new_resource_path)
      end

      resources do |r|
        ret << {r => r.routes(prefix, resource_path: new_resource_path)}
      end

      ret
    end

    def self.describe(hash, context)
      ret = {description: self.desc, actions: {}, resources: {}}

      context.resource = self

      orig_resource_path = context.resource_path
      context.resource_path = context.resource_path + [resource_name.underscore]

      hash[:actions].each do |action, path|
        context.action = action
        context.path = path

        a_name = action.action_name.underscore
        a_desc = action.describe(context)

        ret[:actions][a_name] = a_desc if a_desc
      end

      hash[:resources].each do |resource, children|
        ret[:resources][resource.resource_name.underscore] = resource.describe(children, context)
      end

      context.resource_path = orig_resource_path

      ret
    end

    def self.define_resource(name, superclass: Resource, &block)
      return false if const_defined?(name) && self != HaveAPI::Resource

      cls = Class.new(superclass)
      const_set(name, cls) if self != HaveAPI::Resource
      cls.resource_name = name
      cls.class_exec(&block) if block
      cls
    end

    def self.define_action(name, superclass: Action, &block)
      return false if const_defined?(name)

      cls = Class.new(superclass)
      const_set(name, cls)
      cls.resource = self
      cls.action_name = name
      superclass.delayed_inherited(cls)
      cls.class_exec(&block)
    end
  end
end
