require 'haveapi/go_client/utils'

module HaveAPI::GoClient
  class Resource
    include Utils

    attr_reader :name, :parent, :full_name, :go_name, :go_type
    attr_reader :resources, :actions

    def initialize(parent, name, desc, prefix: nil)
      @parent = parent
      @name = name.to_s
      @prefix = prefix
      @full_name = resource_path.map(&:name).join('_')
      @go_name = camelize(name)
      @go_type = full_go_type
      @resources = desc[:resources].map { |k, v| Resource.new(self, k, v) }
      @actions = desc[:actions].map { |k, v| Action.new(self, k, v, prefix: prefix) }
    end

    def api_version
      tmp = parent
      tmp = tmp.parent until tmp.is_a?(ApiVersion)
      tmp
    end

    def parent_resources
      parents = []
      tmp = parent

      while tmp.is_a?(Resource)
        parents << tmp
        tmp = tmp.parent
      end

      parents.reverse
    end

    def resource_path
      parent_resources + [self]
    end

    def resolve_associations
      actions.each { |a| a.resolve_associations }
      resources.each { |r| r.resolve_associations }
    end

    def generate(gen)
      ErbTemplate.render_to_if_changed(
        'resource.go',
        {
          package: gen.package,
          resource: self,
        },
        File.join(gen.dst, prefix_underscore("resource_#{full_name}.go"))
      )

      resources.each { |r| r.generate(gen) }

      actions.each do |a|
        ErbTemplate.render_to_if_changed(
          'action.go',
          {
            package: gen.package,
            action: a,
          },
          File.join(gen.dst, prefix_underscore("resource_#{full_name}_action_#{a.name}.go"))
        )
      end
    end

    protected
    attr_reader :prefix

    def prefix_underscore(s)
      if prefix
        "#{prefix}_#{s}"
      else
        s
      end
    end

    def prefix_camel(s)
      if prefix
        camelize(prefix) + s
      else
        s
      end
    end

    def full_go_type
      names = ['Resource']
      names.concat(parent_resources.map(&:go_name))
      names << go_name
      prefix_camel(names.join(''))
    end
  end
end
