require 'haveapi/go_client/utils'

module HaveAPI::GoClient
  class Resource
    include Utils

    # Resource name as returned by the API
    # @return [String]
    attr_reader :name

    # Parent resource or API version
    # @return [ApiServer, Resource]
    attr_reader :parent

    # Full name with underscores
    # @return [String]
    attr_reader :full_name

    # Safe full name for generated filenames
    # @return [String]
    attr_reader :file_name

    # Full name with dots
    # @return [String]
    attr_reader :full_dot_name

    # Name in Go
    # @return [String]
    attr_reader :go_name

    # Name of the field in the parent Go struct
    # @return [String]
    attr_reader :go_member_name

    # Type in Go
    # @return [String]
    attr_reader :go_type

    # Child resources
    # @return [Array<Resource>]
    attr_reader :resources

    # Resource actions
    # @return [Array<Action>]
    attr_reader :actions

    def initialize(parent, name, desc, prefix: nil)
      @parent = parent
      @name = name.to_s
      @prefix = prefix
      @full_name = resource_path.map(&:name).join('_')
      @file_name = resource_path.map { |r| safe_file_component(r.name) }.join('_')
      @full_dot_name = resource_path.map(&:name).map(&:capitalize).join('.')
      @go_name = camelize(name)
      @go_type = full_go_type
      @resources = desc[:resources].map do |k, v|
        Resource.new(self, k, v)
      end.sort!
      @actions = desc[:actions].map do |k, v|
        Action.new(self, k.to_s, v, prefix:)
      end.sort!
      self.class.allocate_member_names(@resources, @actions, reserved: %w[Client])
    end

    # @param resources [Array<Resource>]
    # @param actions [Array<Action>]
    # @param reserved [Array<String>]
    def self.allocate_member_names(resources, actions, reserved:)
      allocator = MemberNameAllocator.new(reserved)

      resources.each do |resource|
        resource.assign_go_member_name(
          allocator.allocate(
            resource.go_name,
            suffix: 'Resource',
            identity: "resource:#{resource.resource_path.map(&:name).join('/')}"
          )
        )
      end

      actions.each { |action| action.allocate_member_names(allocator) }
    end

    # @param name [String]
    def assign_go_member_name(name)
      @go_member_name = name
    end

    # @return [ApiVersion]
    def api_version
      tmp = parent
      tmp = tmp.parent until tmp.is_a?(ApiVersion)
      tmp
    end

    # @return [Array<Resource>]
    def parent_resources
      parents = []
      tmp = parent

      while tmp.is_a?(Resource)
        parents << tmp
        tmp = tmp.parent
      end

      parents.reverse
    end

    # @return [Array<Resource>]
    def resource_path
      parent_resources + [self]
    end

    def resolve_associations
      actions.each(&:resolve_associations)
      resources.each(&:resolve_associations)
    end

    def generate(gen)
      ErbTemplate.render_to_if_changed(
        'resource.go',
        {
          package: gen.package,
          resource: self
        },
        File.join(gen.dst, prefix_underscore("resource_#{file_name}.go"))
      )

      resources.each { |r| r.generate(gen) }

      actions.each do |a|
        ErbTemplate.render_to_if_changed(
          'action.go',
          {
            package: gen.package,
            action: a
          },
          File.join(gen.dst, prefix_underscore("resource_#{file_name}_action_#{a.file_name}.go"))
        )
      end
    end

    def <=>(other)
      [go_name, name] <=> [other.go_name, other.name]
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
      prefix_camel(names.join)
    end
  end
end
