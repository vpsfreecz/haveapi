module HaveAPI::TypeScriptClient
  class IR
    TYPES = %w[String Text Integer Float Boolean Datetime Resource Custom].freeze
    LAYOUTS = %w[object object_list hash hash_list].freeze
    METHODS = %w[GET DELETE POST PUT PATCH].freeze

    def self.build(snapshot)
      new(snapshot).build
    end

    def initialize(snapshot)
      @snapshot = Snapshot.validate(snapshot)
      @exports = Naming::Scope.new(Naming::EXPORT_RESERVED)
      @actions = []
    end

    def build
      description = @snapshot.fetch('description')
      namespace = description.dig('meta', 'namespace')
      fail_at('invalid metadata namespace', %w[meta namespace]) unless namespace.is_a?(String) && !namespace.empty?
      fail_at('reserved metadata namespace', %w[meta namespace]) if Naming::RESERVED.include?(namespace)

      resources = walk(description.fetch('resources'), [])
      description.fetch('authentication').sort.each do |provider, config|
        next unless config.has_key?('resources')

        # Validate separately: these API-root routes belong to the runtime's
        # authentication implementation, outside the version-root executor.
        self.class.new(@snapshot).send(:walk, config['resources'], ['authentication', provider], authentication: true)
      end
      freeze_data({
        api_version: @snapshot.fetch('api_version'), schema_sha256: Snapshot.sha256(@snapshot),
        metadata_namespace: namespace, resources: resources,
        actions: @actions.sort_by { |action| action[:schema_path] }
      })
    end

    private

    def fail_at(message, path)
      raise Error, "#{message} at #{path.join('/')}"
    end

    def walk(map, parents, authentication: false)
      fail_at('resources must be an object', parents) unless map.is_a?(Hash)

      scope = Naming::Scope.new
      map.sort.map do |name, desc|
        path = parents + [name]
        fail_at('resource must be an object', path) unless desc.is_a?(Hash)

        accessor = authentication && parents.length == 2 ? Naming.identifier(path.join('__')) : Naming.identifier(name)
        scope.add(accessor, path.join('/'))
        export = Naming.export(path)
        @exports.add("#{export}Resource", "#{path.join('/')} (Resource)")
        children = walk(desc.fetch('resources'), path, authentication:)
        member_scope = Naming::Scope.new
        children.each { |child| member_scope.add(child[:accessor_name], child[:schema_path].join('/')) }
        action_map = desc.fetch('actions')
        fail_at('actions must be an object', path) unless action_map.is_a?(Hash)

        actions = action_map.sort.map { |action_name, action| action_record(action_name, action, path, member_scope, authentication:) }
        { schema_path: path, export_name: export, accessor_name: accessor, children:, actions: }
      end
    rescue KeyError => e
      fail_at("missing #{e.key}", parents)
    end

    def action_record(name, desc, parents, scope, authentication:)
      path = parents + [name]
      fail_at('action must be an object', path) unless desc.is_a?(Hash)
      accessor = scope.add(Naming.identifier(name), path.join('/'))
      export = Naming.export(path)
      %w[Path Input Output GlobalInput GlobalOutput ObjectInput ObjectOutput Options].each do |suffix|
        @exports.add("#{export}#{suffix}", "#{path.join('/')} (#{suffix})")
      end
      aliases = desc.fetch('aliases', [])
      fail_at('aliases must be an array of strings', path) unless aliases.is_a?(Array) && aliases.all?(String)
      aliases.each { |item| scope.add(Naming.identifier(item), (path + ['alias', item]).join('/')) }
      %w[auth blocking].each do |key|
        next unless desc.has_key?(key)

        fail_at("#{key} must be boolean or null", path) unless [true, false, nil].include?(desc[key])
      end
      route = route(desc['path'], path, authentication:)
      placeholders = route.scan(/\{([^}]+)\}/).flatten.uniq
      placeholder_scope = Naming::Scope.new
      placeholders.each { |item| placeholder_scope.add(Naming.identifier(item), (path + ['path', item]).join('/')) }
      action = {
        schema_path: path, export_name: export, accessor_name: accessor, aliases:, method: desc['method'],
        path_template: route, placeholders:, auth: desc.fetch('auth', true) != false, blocking: desc['blocking'] == true,
        input: io(desc['input'], path + ['input'], input: true), output: io(desc['output'], path + ['output'])
      }
      metadata = desc['meta'] || {}
      fail_at('metadata must be an object', path + ['meta']) unless metadata.is_a?(Hash)
      unknown = metadata.keys - %w[global object]
      fail_at("unsupported metadata roles #{unknown.join(', ')}", path + ['meta']) unless unknown.empty?
      %w[global object].each do |role|
        group = metadata[role] || {}
        fail_at('metadata role must be an object', path + ['meta', role]) unless group.is_a?(Hash)
        %w[input output].each do |direction|
          action[:"#{role}_#{direction}"] = io(group[direction], path + ['meta', role, direction], input: direction == 'input', metadata: true)
        end
      end
      if %w[GET OPTIONS].include?(desc['method']) && action[:object_input]
        fail_at('unsupported query object-input metadata', path + %w[meta object input])
      end
      fail_at('unsupported HTTP method', path) unless METHODS.include?(desc['method'])
      namespace = @snapshot.fetch('description').fetch('meta').fetch('namespace')
      if action[:object_input] && action[:input]&.fetch(:parameters)&.any? { |field| [field[:wire_name], field[:emitted_name]].include?(namespace) }
        fail_at('object metadata namespace collides with input field', path + ['input', namespace])
      end
      if action[:object_output] && action[:output]&.fetch(:parameters)&.any? { |field| field[:wire_name] == namespace }
        fail_at('object metadata namespace collides with output field', path + ['output', namespace])
      end
      @actions << action
      action
    end

    def io(desc, path, input: false, metadata: false)
      return nil if desc.nil? || desc == { 'parameters' => {} }

      fail_at('IO must be an object', path) unless desc.is_a?(Hash)
      fail_at('unsupported Custom IO format', path) if desc.has_key?('format')
      fail_at('unsupported layout', path) unless LAYOUTS.include?(desc['layout'])
      if input && desc['layout'].end_with?('_list')
        fail_at('unsupported input list', path)
      end
      namespace = desc['namespace']
      unless namespace == false || (namespace.is_a?(String) && !namespace.empty?)
        fail_at('unsupported namespace', path)
      end
      fail_at('unsupported output namespace=false', path) if !input && !metadata && namespace == false
      parameters = desc['parameters']
      fail_at('parameters must be an object', path) unless parameters.is_a?(Hash)
      scope = Naming::Scope.new
      fields = parameters.sort.map { |name, parameter| parameter_record(name, parameter, path, scope) }
      { layout: desc['layout'], namespace:, parameters: fields }
    end

    def parameter_record(name, desc, parents, scope)
      path = parents + [name]
      fail_at('parameter must be an object', path) unless desc.is_a?(Hash)
      fail_at("unsupported parameter type #{desc['type'].inspect}", path) unless TYPES.include?(desc['type'])
      %w[required nullable protected].each do |key|
        next unless desc.has_key?(key)

        fail_at("#{key} must be boolean or null", path) unless [true, false, nil].include?(desc[key])
      end
      validators = desc.fetch('validators', {})
      fail_at('validators must be an object', path) unless validators.is_a?(Hash)
      association = nil
      if desc['type'] == 'Resource'
        resource = desc['resource']
        unless resource.is_a?(Array) && !resource.empty? && resource.all? { |item| item.is_a?(String) && !item.empty? } &&
               %w[value_id value_label].all? { |key| desc[key].is_a?(String) && !desc[key].empty? }
          fail_at('invalid resource association', path)
        end
        association = { resource_path: resource, value_id: desc['value_id'], value_label: desc['value_label'] }
      end
      {
        wire_name: name, emitted_name: scope.add(Naming.identifier(name), path.join('/')), kind: desc['type'],
        required: desc['required'] == true, nullable: desc['nullable'] == true, protected: desc['protected'] == true,
        association:, validators:
      }
    end

    def route(path, schema_path, authentication:)
      fail_at('unsafe action path', schema_path) unless path.is_a?(String) && Snapshot.safe_path?(path)
      mount = @snapshot.fetch('mount_path')
      fail_at('action path escapes capture mount', schema_path) unless path.start_with?(mount)
      relative = path.delete_prefix(mount)
      version = "v#{@snapshot.fetch('api_version')}"
      segments = relative.split('/', -1)
      if segments.first == version
        segments.shift
      elsif !authentication
        fail_at('action path differs from selected API version', schema_path)
      elsif segments.first&.match?(/\Av\d+(?:\.\d+)*\z/)
        fail_at('authentication action selects another API version', schema_path)
      end
      relative = segments.join('/')
      unless !relative.empty? && relative.split('/').all? { |segment| segment.empty? || segment.match?(/\A(?:[a-zA-Z0-9_.%~-]+|\{[a-zA-Z0-9_-]+\})\z/) }
        fail_at('unsupported action path template', schema_path)
      end
      "/#{relative}"
    end

    def freeze_data(value)
      case value
      when Hash
        value.each do |key, item|
          freeze_data(key)
          freeze_data(item)
        end
      when Array
        value.each { |item| freeze_data(item) }
      end
      value.freeze
    end
  end
end
