module HaveAPI
  class Resource < Common
    obj_type :resource
    has_attr :version
    has_attr :desc
    has_attr :model
    has_attr :route
    has_attr :auth, true

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

        begin
          if obj.obj_type == :action
            yield obj
          end

        rescue NoMethodError
          next
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

    def self.routes(prefix='/')
      ret = []
      prefix = "#{prefix}#{@route || to_s.demodulize.tableize}/"

      actions do |a|
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
  end
end
