require 'erb'
require 'json'

module HaveAPI::TypeScriptClient
  # Templates are source inputs loaded once, outside the pure emission seam.
  class Emitter
    TEMPLATE_ROOT = File.expand_path('../../../template', __dir__).freeze
    TEMPLATES = %w[action api index resource runtime types].to_h do |name|
      [name, File.read(File.join(TEMPLATE_ROOT, "#{name}.ts.erb"), encoding: 'UTF-8').freeze]
    end.freeze
    IO_SUFFIXES = {
      input: 'Input', output: 'Output', global_input: 'GlobalInput',
      global_output: 'GlobalOutput', object_input: 'ObjectInput', object_output: 'ObjectOutput'
    }.freeze

    def initialize(ir, config)
      @ir = ir
      @runtime_import = config.fetch(:runtime_import) { config.fetch('runtime_import') }
    end

    # Sorted relative filenames and deterministic UTF-8/LF source; no side effects.
    def files
      plan = file_plan
      validate_paths(plan)
      @resource_paths = plan.select { |item| item[:template] == 'resource' }.to_h { |item| [item[:record].fetch(:schema_path), item[:path]] }
      @action_paths = plan.select { |item| item[:template] == 'action' }.to_h { |item| [item[:record].fetch(:schema_path), item[:path]] }
      plan.sort_by { |item| item.fetch(:path) }.to_h do |item|
        @current_path = item.fetch(:path)
        @record = item[:record]
        content = ERB.new(TEMPLATES.fetch(item.fetch(:template)), trim_mode: '-').result(binding)
        [@current_path, content.gsub("\r\n", "\n").encode('UTF-8')]
      end
    end

    private

    def file_plan
      plan = %w[api index runtime types].map { |name| { path: "#{name}.ts", template: name, origin: "generated root #{name}" } }
      walk = lambda do |items, parent|
        items.each do |resource|
          directory = "#{parent}resources/#{resource.fetch(:accessor_name)}/"
          plan << { path: "#{directory}resource.ts", template: 'resource', record: resource, origin: resource.fetch(:schema_path).join('/') }
          resource.fetch(:actions).each do |action|
            plan << { path: "#{directory}actions/#{action.fetch(:accessor_name)}.ts", template: 'action', record: action, origin: action.fetch(:schema_path).join('/') }
          end
          walk.call(resource.fetch(:children), directory)
        end
      end
      walk.call(@ir.fetch(:resources), '')
      plan
    end

    def validate_paths(plan)
      entries = {}
      plan.each do |item|
        path = item.fetch(:path)
        segments = path.split('/', -1)
        unless path.ascii_only? && !path.match?(/[\\\x00-\x1f\x7f]/) && segments.all? { |segment| segment.match?(/\A[a-zA-Z0-9_$.]+\z/) && !%w[. ..].include?(segment) }
          raise Error, "unsafe generated path #{path.inspect} for #{item.fetch(:origin)}"
        end

        segments.each_index do |index|
          prefix = segments.take(index + 1).join('/')
          key = prefix.downcase
          kind = index == segments.length - 1 ? :file : :directory
          previous = entries[key]
          if previous && (previous[:path] != prefix || previous[:kind] != kind || kind == :file)
            raise Error, "generated path collision #{prefix}: #{previous[:origin]} (#{previous[:path]}) and #{item.fetch(:origin)} (#{path})"
          end

          entries[key] ||= { path: prefix, kind:, origin: item.fetch(:origin) }
        end
      end
    end

    def relative_import(target)
      from = @current_path.split('/')[0...-1]
      to = target.split('/')
      while !from.empty? && from.first == to.first
        from.shift
        to.shift
      end
      path = (Array.new(from.length, '..') + to).join('/').sub(/\.ts\z/, '.js')
      path.start_with?('.') ? path : "./#{path}"
    end

    def public_type_exports
      resource_exports = resources.map do |resource|
        [@resource_paths.fetch(resource.fetch(:schema_path)), ["#{resource.fetch(:export_name)}Resource"]]
      end
      action_exports = @ir.fetch(:actions).map do |action|
        names = [*IO_SUFFIXES.values, 'Path', 'Options'].map { |suffix| action_type(action, suffix) }
        [@action_paths.fetch(action.fetch(:schema_path)), names]
      end
      (resource_exports + action_exports).sort.map do |path, names|
        "export type {#{names.join(', ')}} from #{literal(relative_import(path))};"
      end
    end

    def literal(value)
      JSON.generate(value).gsub("\u2028", '\\u2028').gsub("\u2029", '\\u2029')
    end

    def resources
      flatten = lambda do |items|
        items.flat_map { |resource| [resource] + flatten.call(resource.fetch(:children)) }
      end
      flatten.call(@ir.fetch(:resources))
    end

    def action_type(action, suffix)
      "#{action.fetch(:export_name)}#{suffix}"
    end

    def parameter_type(parameter, input:, query: false)
      kind = parameter.fetch(:kind)
      case kind
      when 'String', 'Text', 'Datetime' then 'string'
      when 'Boolean' then 'boolean'
      when 'Integer', 'Float' then 'number'
      when 'Resource'
        return 'number' if input

        association = parameter.fetch(:association)
        keys = [association.fetch(:value_id), association.fetch(:value_label)].uniq
        "Partial<Record<#{keys.map { |key| literal(key) }.join(' | ')}, unknown>>"
      when 'Custom'
        return 'unknown' unless input

        query ? 'string | number | boolean' : 'Exclude<JsonValue, null>'
      else
        raise Error, "unsupported emitter parameter kind #{kind}"
      end
    end

    def fields(io, input:, query: false)
      return [] unless io

      io.fetch(:parameters).map do |parameter|
        # Output is an unchanged wire DTO. Input accessors map back to wire keys.
        name = parameter.fetch(input ? :emitted_name : :wire_name)
        optional = !input || !parameter.fetch(:required)
        nullable = !input || parameter.fetch(:nullable)
        type = parameter_type(parameter, input:, query:)
        type += ' | null' if nullable && type != 'unknown'
        type += ' | undefined' if input && optional
        "  #{literal(name)}#{'?' if optional}: #{type};"
      end
    end

    def required?(io)
      io && io.fetch(:parameters).any? { |parameter| parameter.fetch(:required) }
    end

    def params_required?(action)
      required?(action[:input]) || required?(action[:object_input])
    end

    def options_required?(action)
      !action.fetch(:placeholders).empty? || params_required?(action) || required?(action[:global_input])
    end

    def action_declarations(action)
      query = %w[GET OPTIONS].include?(action.fetch(:method))
      declarations = []
      IO_SUFFIXES.each do |key, suffix|
        io = action[key]
        input = key.to_s.end_with?('input')
        lines = fields(io, input:, query: input && query)
        if key == :input && action[:object_input]
          namespace = @ir.fetch(:metadata_namespace)
          if io && io.fetch(:parameters).any? { |parameter| [parameter[:wire_name], parameter[:emitted_name]].include?(namespace) }
            raise Error, "object metadata collides with input field at #{action.fetch(:schema_path).join('/')}"
          end

          optional = !required?(action[:object_input])
          lines << "  #{literal(namespace)}#{'?' if optional}: #{action_type(action, 'ObjectInput')}#{' | undefined' if optional};"
        elsif key == :output && io && io.fetch(:layout) == 'object_list' && action[:object_output]
          lines << "  #{literal(@ir.fetch(:metadata_namespace))}?: #{action_type(action, 'ObjectOutput')} | null;"
        end
        shape = lines.empty? ? 'Record<string, never>' : "{\n#{lines.join("\n")}\n}"
        shape = "Array<#{shape}>" if io && io.fetch(:layout).end_with?('_list')
        shape = 'unknown' if key == :output && io.nil?
        declarations << "export type #{action_type(action, suffix)} = #{shape};"
      end
      paths = action.fetch(:placeholders).map { |name| "  #{literal(Naming.identifier(name))}: string | number;" }
      declarations << "export type #{action_type(action, 'Path')} = #{paths.empty? ? 'Record<string, never>' : "{\n#{paths.join("\n")}\n}"};"
      options = []
      options << "  path#{'?' if paths.empty?}: #{paths.empty? ? 'undefined' : action_type(action, 'Path')};"
      has_params = action[:input] || action[:object_input]
      params_type = has_params ? action_type(action, 'Input') : 'undefined'
      params_type += ' | undefined' if has_params && !params_required?(action)
      options << "  params#{'?' unless params_required?(action)}: #{params_type};"
      meta_type = action[:global_input] ? action_type(action, 'GlobalInput') : 'undefined'
      meta_type += ' | undefined' if action[:global_input] && !required?(action[:global_input])
      options << "  meta#{'?' unless required?(action[:global_input])}: #{meta_type};"
      options << "  headers?: RequestSpec['headers'];"
      options << "  signal?: RequestSpec['signal'];"
      options << "  timeoutMs?: RequestSpec['timeoutMs'];"
      declarations << "export interface #{action_type(action, 'Options')} {\n#{options.join("\n")}\n}"
      declarations.join("\n\n")
    end

    def action_names(action)
      [action.fetch(:accessor_name)] + action.fetch(:aliases).map { |name| Naming.identifier(name) }
    end

    def resource_declaration(resource)
      members = resource.fetch(:children).map do |child|
        "  readonly #{literal(child.fetch(:accessor_name))}: #{child.fetch(:export_name)}Resource;"
      end
      resource.fetch(:actions).each do |action|
        action_names(action).each do |name|
          members << "  readonly #{literal(name)}: (options#{'?' unless options_required?(action)}: #{action_type(action, 'Options')}) => Promise<RequestResult<#{action_type(action, 'Output')}>>;"
        end
      end
      "export interface #{resource.fetch(:export_name)}Resource {\n#{members.join("\n")}\n}"
    end

    def field_definitions(io)
      return nil unless io

      io.fetch(:parameters).map do |parameter|
        parameter.slice(:wire_name, :emitted_name, :kind, :required, :nullable)
      end
    end

    def action_definition(action)
      {
        method: action.fetch(:method), path: action.fetch(:path_template),
        placeholders: action.fetch(:placeholders).map { |name| [name, Naming.identifier(name)] },
        inputNamespace: (action[:input] && action[:input][:namespace]) || nil,
        outputNamespace: (action[:output] && action[:output][:namespace]) || nil,
        metaNamespace: @ir.fetch(:metadata_namespace), input: field_definitions(action[:input]),
        globalInput: field_definitions(action[:global_input]), objectInput: field_definitions(action[:object_input])
      }
    end
  end
end
