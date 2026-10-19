module HaveAPI::RustClient
  class IR
    TYPES = %w[String Text Integer Float Boolean Datetime Resource Custom].freeze
    LAYOUTS = %w[object object_list hash hash_list].freeze
    METHODS = %w[GET DELETE POST PUT PATCH].freeze
    attr_reader :snapshot, :resources, :actions

    def initialize(snapshot)
      @snapshot = Snapshot.validate(snapshot)
      @resources = []
      @actions = []
      @module_scope = Naming::Scope.new(%w[runtime resources API_SPEC API_VERSION SCHEMA_SHA256 builder config])
      description = snapshot.fetch('description')
      walk(description.fetch('resources'), [])
      description.fetch('authentication').each do |provider, auth|
        next unless auth['resources']

        walk(auth.fetch('resources'), ['authentication', provider], auth_provider: provider)
      end
      bind_ancestors
      validate_auth(description.fetch('authentication'))
    end

    def inventory
      {
        'api_version' => snapshot.fetch('api_version'), 'schema_sha256' => Snapshot.sha256(snapshot),
        'profile' => snapshot.fetch('profile'), 'coverage' => 'captured description only; plugin coverage unknown',
        'resource_count' => resources.length, 'action_count' => actions.length,
        'parameter_count' => actions.sum { |action| all_parameters(action).length },
        'resources' => resources.map { |resource| resource[:path] },
        'actions' => actions.map do |action|
          { 'name' => action[:path], 'method' => action[:desc].fetch('method'),
            'path' => action[:desc].fetch('path'),
            'parameters' => all_parameters(action).map { |parameter| parameter[:path] } }
        end
      }
    end

    def all_parameters(action)
      %i[input output global_input global_output object_input object_output].flat_map do |key|
        action[key] ? action[key][:parameters] : []
      end
    end

    private

    def walk(map, parents, auth_provider: nil)
      raise Error, "resources must be an object at #{parents.join('/')}" unless map.is_a?(Hash)

      map.sort.each do |name, desc|
        path = parents + [name]
        module_name = path.map { |item| Naming.snake(item) }.join('__')
        @module_scope.add(module_name, path.join('/'))
        resource = { name:, path:, module: module_name, desc:, actions: [], parent: parents }
        resources << resource
        scope = Naming::Scope.new
        desc.fetch('actions').sort.each do |action_name, action_desc|
          action_path = path + [action_name]
          method_name = Naming.snake(action_name)
          scope.add(method_name, action_path.join('/'))
          aliases = action_desc.fetch('aliases', []).map do |item|
            alias_name = Naming.snake(item)
            next if alias_name == method_name

            scope.add(alias_name, (action_path + [item]).join('/'))
          end.compact
          action = {
            name: action_name, method: method_name, aliases:, path: action_path, resource:,
            desc: action_desc, auth_provider:, route: route(action_desc.fetch('path'), auth_provider),
            input: io(action_desc['input'], :input, action_path + ['input']),
            output: io(action_desc['output'], :output, action_path + ['output'])
          }
          raise Error, "unsupported HTTP method at #{action_path.join('/')}" unless METHODS.include?(action_desc['method'])

          %w[global object].each do |role|
            %w[input output].each do |direction|
              action[:"#{role}_#{direction}"] = io(
                action_desc.dig('meta', role, direction), :metadata, action_path + ['meta', role, direction]
              )
            end
          end
          action[:placeholders] = action[:route].scan(/\{([^}]+)\}/).flatten.uniq
          argument_scope = Naming::Scope.new(%w[self path_params])
          action[:arguments] = action[:placeholders].to_h do |placeholder|
            [placeholder, argument_scope.add(Naming.snake(placeholder), action_path.join('/') + "/#{placeholder}")]
          end
          resource[:actions] << action
          actions << action
        end
        walk(desc.fetch('resources'), path, auth_provider:)
      end
    rescue KeyError => e
      raise Error, "incomplete resource description at #{parents.join('/')}: #{e.key}"
    end

    def io(desc, direction, path)
      return nil if desc.nil? || desc == { 'parameters' => {} }
      raise Error, "invalid IO at #{path.join('/')}" unless desc.is_a?(Hash)
      raise Error, "unsupported layout at #{path.join('/')}" unless LAYOUTS.include?(desc['layout'])

      namespace = desc['namespace']
      unless namespace == false || (namespace.is_a?(String) && !namespace.empty?)
        raise Error, "missing/invalid namespace at #{path.join('/')}"
      end
      if direction == :output && namespace == false
        raise Error, "ordinary output namespace=false unsupported at #{path.join('/')}"
      end
      if direction == :input && namespace == false && desc['layout'].end_with?('_list')
        raise Error, "unnamespaced list input unsupported at #{path.join('/')}"
      end

      parameters = desc.fetch('parameters')
      raise Error, "parameters must be an object at #{path.join('/')}" unless parameters.is_a?(Hash)
      raise Error, "custom IO format unsupported at #{path.join('/')}" if desc.has_key?('format')

      scope = Naming::Scope.new(direction == :input ? %w[new input global_meta object_meta send input_mut prepared] : %w[extra object_meta])
      fields = parameters.sort.map do |name, parameter|
        unless parameter.is_a?(Hash) && TYPES.include?(parameter['type'])
          raise Error, "unknown parameter type at #{(path + [name]).join('/')}"
        end

        field = scope.add(Naming.snake(name), (path + [name]).join('/'))
        { name:, field:, desc: parameter, path: path + [name] }
      end
      if direction == :input
        fields.select { |parameter| parameter[:desc]['nullable'] == true }.each do |parameter|
          scope.add("#{parameter[:field]}_null", (parameter[:path] + ['null setter']).join('/'))
        end
      end
      { desc:, parameters: fields, layout: desc.fetch('layout'), namespace: namespace == false ? nil : namespace }
    end

    def route(path, provider)
      unless path.is_a?(String) && path.start_with?('/') && !path.match?(/[?#]/) && Snapshot.safe_segments?(path)
        raise Error, 'unsafe action path in schema'
      end

      mount = snapshot.fetch('mount_path')
      raise Error, 'action path escapes capture mount' unless path.start_with?(mount)

      relative = path.delete_prefix(mount)
      unless provider || relative.start_with?("v#{snapshot.fetch('api_version')}/")
        raise Error, 'action path does not match selected API version'
      end
      unless relative.gsub(/\{[a-zA-Z0-9_-]+\}/, '').match?(%r{\A[a-zA-Z0-9_/.%~-]*\z})
        raise Error, 'invalid action path/template'
      end

      relative
    end

    def bind_ancestors
      resources.each do |resource|
        parent = resources.find { |item| item[:path] == resource[:parent] }
        resource[:bound] = []
        next unless parent

        parent_routes = parent[:actions].map { |action| action[:route] }
        ancestors = resource[:actions].map do |action|
          matches = parent_routes.filter_map do |route|
            next unless action[:route].start_with?("#{route}/")

            route.scan(/\{([^}]+)\}/).flatten.uniq
          end
          matches.max_by(&:length) || []
        end
        unique = ancestors.uniq
        if unique.length > 1
          raise Error, "ambiguous ancestor placeholders at #{resource[:path].join('/')}"
        end

        resource[:bound] = unique.first || []
        resource[:actions].each do |action|
          next if action[:placeholders].take(resource[:bound].length) == resource[:bound]

          raise Error, "ancestor template mismatch at #{action[:path].join('/')}"
        end
      end
    end

    def validate_auth(auth)
      auth.each do |provider, config|
        next unless config.is_a?(Hash)

        config.each do |key, value|
          Snapshot.endpoint!(value) if key.end_with?('_url') && value
          next unless key.end_with?('_path') && value
          next if value.start_with?('/') && !value.match?(/[?#]/) && Snapshot.safe_segments?(value)

          raise Error, "unsafe authentication endpoint for #{provider}"
        end
      end
    end
  end
end
