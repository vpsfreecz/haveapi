require_relative '../typescript_client'
require 'uri'

module HaveAPI::TypeScriptClient
  # Names belong to the complete SDK; request-local help only limits their use.
  class Documentation
    class Unsupported < StandardError; end

    def self.from_description(description:, api_version:, protocol_version:, mount_path:, package_name:, package_version: nil)
      snapshot = Snapshot.from_description(
        description: JSON.parse(JSON.generate(description)), api_version:, protocol_version:, mount_path:,
        source_url: "https://haveapi.invalid#{mount_path}v#{api_version}/", profile: 'server-documentation'
      )
      from_snapshot(snapshot:, package_name:, package_version:)
    end

    def self.from_snapshot(snapshot:, package_name:, package_version: nil)
      new(snapshot:, package_name:, package_version:)
    end

    def initialize(snapshot:, package_name:, package_version: nil)
      name_pattern = %r{\A(?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*\z}
      semver = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z/
      unless package_name.is_a?(String) && package_name.length <= 214 && package_name.match?(name_pattern) &&
             !%w[node_modules favicon.ico].include?(package_name) &&
             (package_version.nil? || (package_version.is_a?(String) && package_version.match?(semver) &&
              package_version.split('+', 2).first.split('-', 2).last.split('.').none? { |part| part.match?(/\A0\d+\z/) }))
        raise Error, 'Invalid TypeScript documentation package identity'
      end

      @package_name = package_name.dup.freeze
      @package_version = package_version&.dup&.freeze
      @snapshot = Snapshot.validate(JSON.parse(Snapshot.canonical(snapshot)))
      @ir = IR.build(@snapshot)
      @index = {}
      @accessors = {}
      index_resources(@ir.fetch(:resources), [])
      freeze_data(@snapshot)
      freeze_data(@index)
      freeze_data(@accessors)
      freeze
    end

    def resolve(resource_path:, action_name:)
      @index[[resource_path.map(&:to_s), action_name.to_s]]
    end

    def render(kind:, context:, mode: :async, auth_method: nil, auth_description: nil)
      unsupported! unless mode == :async && context.version.to_s == @snapshot.fetch('api_version')
      source = case kind
               when :init then program(context, ['void api;'])
               when :auth then program(context, ['void api;'], authentication(context, auth_method, auth_description))
               when :example then example(context)
               else unsupported!
               end
      { status: :code, code: source.freeze }.freeze
    rescue Unsupported, JSON::GeneratorError, EncodingError
      # Never name fields or actions from the private SDK in public diagnostics.
      { status: :limitation, reason: 'This sample is unavailable or incompatible with the configured TypeScript SDK.'.freeze }.freeze
    end

    private

    def unsupported!
      raise Unsupported
    end

    def freeze_data(value)
      case value
      when Hash then value.each do |key, item|
        freeze_data(key)
        freeze_data(item)
      end
      when Array then value.each { |item| freeze_data(item) }
      end
      value.freeze
    end

    def normalize(value)
      case value
      when Hash then value.to_h { |key, item| [key.to_s, normalize(item)] }
      when Array then value.map { |item| normalize(item) }
      when Symbol then value.to_s
      else value
      end
    end

    def index_resources(resources, parents)
      resources.each do |resource|
        accessors = (parents + [resource.fetch(:accessor_name)]).freeze
        resource.fetch(:actions).each do |action|
          names = [action.fetch(:schema_path).last] + action.fetch(:aliases)
          names.each { |name| @index[[action.fetch(:schema_path)[0...-1], name].freeze] = action }
          @accessors[action.fetch(:schema_path)] = accessors
        end
        index_resources(resource.fetch(:children), accessors)
      end
    end

    def literal(value)
      return "{#{value.map { |key, item| "#{key == '__proto__' ? '["__proto__"]' : literal(key)}:#{literal(item)}" }.join(',')}}" if value.is_a?(Hash)
      return "[#{value.map { |item| literal(item) }.join(',')}]" if value.is_a?(Array)

      JSON.generate(value).gsub("\u2028", '\\u2028').gsub("\u2029", '\\u2029')
    end

    def program(context, body, auth = [])
      version_url = context.version_url.to_s.sub(%r{/+\z}, '')
      uri = URI.parse(version_url)
      unsupported! unless uri.is_a?(URI::HTTP) && uri.host && !uri.userinfo && !uri.query && !uri.fragment &&
                          uri.path.end_with?("/v#{@snapshot.fetch('api_version')}") && Snapshot.safe_path?(uri.path)
      dependencies = "// Configured SDK: #{@package_name}#{"@#{@package_version}" if @package_version}; runtime: haveapi-client@0.30.2."
      lines = [dependencies, "import {AsyncClient, AsyncError} from 'haveapi-client';", "import {createClient} from #{literal(@package_name)};"]
      unless auth.empty?
        lines += ["import {env} from 'node:process';", '', 'function credential(name: string): string {', '  const value = env[name];',
                  '  if (!value) throw new Error(`Missing environment variable ${name}`);', '  return value;', '}']
      end
      lines += ['', 'async function main(): Promise<void> {', "  const runtime = new AsyncClient(#{literal(version_url)});"]
      lines.concat(auth.map { |line| "  #{line}" })
      lines << '  const api = createClient({execute: spec => runtime.request(spec)});'
      lines.concat(body.map { |line| "  #{line}" })
      lines.push('}', '', 'main().catch(error => { throw error; });', '').join("\n")
    rescue URI::InvalidURIError
      unsupported!
    end

    def authentication(context, method, description = nil)
      providers = normalize(context.description)['authentication'] || {}
      saved = @snapshot.fetch('description').fetch('authentication')
      live = providers[method.to_s]
      stored = saved[method.to_s]
      unsupported! unless live.is_a?(Hash) && stored.is_a?(Hash)
      unsupported! if description && normalize(description) != live
      case method.to_s
      when 'basic'
        ['await runtime.authenticate(\'basic\', {user: credential("HAVEAPI_USER"), password: credential("HAVEAPI_PASSWORD")});']
      when 'token'
        header = live['http_header']
        unsupported! unless header.is_a?(String) && header.match?(/\A[!#$%&'*+.^_`|~0-9A-Za-z-]+\z/) && stored['http_header'] == header
        ['await runtime.authenticate(\'token\', {token: credential("HAVEAPI_TOKEN")});']
      else unsupported!
      end
    end

    def action_authentication(action, context)
      return [] unless action.fetch(:auth)

      live = normalize(context.description).fetch('authentication', {})
      %w[basic token].each do |method|
        next unless live.has_key?(method) && @snapshot.fetch('description').fetch('authentication').has_key?(method)

        return authentication(context, method)
      end
      unsupported!
    end

    def authorized_action(context)
      description = normalize(context.description)
      resources = description['resources']
      resource = nil
      context.resource_path.each do |name|
        resource = resources.is_a?(Hash) && resources[name.to_s]
        return nil unless resource.is_a?(Hash)

        resources = resource['resources']
      end
      actions = resource && resource['actions']
      return nil unless actions.is_a?(Hash)
      return actions[context.action_name.to_s] if actions.has_key?(context.action_name.to_s)

      aliases = actions.values.select { |action| Array(action['aliases']).include?(context.action_name.to_s) }
      aliases.one? ? aliases.first : nil
    end

    def saved_action(action)
      current = @snapshot.fetch('description')
      action.fetch(:schema_path)[0...-1].each { |name| current = current.fetch('resources').fetch(name) }
      current.fetch('actions').fetch(action.fetch(:schema_path).last)
    end

    def compatible_action!(action, saved, live, context)
      unsupported! unless live.is_a?(Hash)
      expected_path = URI.parse(context.version_url.to_s).path.sub(%r{/+\z}, '') + action.fetch(:path_template)
      unsupported! unless live['path'] == expected_path && live['method'] == action.fetch(:method) &&
                          (live['auth'] != false) == action.fetch(:auth) && (live['blocking'] == true) == action.fetch(:blocking)
      unsupported! unless normalize(context.description).dig('meta', 'namespace') == @ir.fetch(:metadata_namespace)
      %w[input output].each do |direction|
        left = saved[direction]
        right = live[direction]
        next if empty_io?(left) && empty_io?(right)

        unsupported! unless left.is_a?(Hash) && right.is_a?(Hash) && %w[layout namespace format].all? { |key| left[key] == right[key] }
      end
      %w[global object].each do |role|
        [saved, live].each do |description|
          parameters = description.dig('meta', role, 'input', 'parameters') || {}
          unsupported! if parameters.any? { |_name, parameter| parameter['required'] == true }
        end
      end
    rescue URI::InvalidURIError
      unsupported!
    end

    def empty_io?(value)
      value.nil? || value == { 'parameters' => {} }
    end

    def compatible_parameter?(saved, live)
      saved.is_a?(Hash) && live.is_a?(Hash) &&
        %w[type resource value_id value_label].all? { |key| saved[key] == live[key] } &&
        %w[required nullable].all? { |key| (saved[key] == true) == (live[key] == true) }
    end

    def valid_json?(value)
      case value
      when Hash then value.all? { |key, item| key.is_a?(String) && valid_json?(item) }
      when Array then value.all? { |item| valid_json?(item) }
      when Float then value.finite?
      when Integer then value.abs <= 9_007_199_254_740_991
      when String, TrueClass, FalseClass, NilClass then true
      else false
      end
    end

    def valid_value?(parameter, value, output: false, query: false)
      return output || parameter['nullable'] == true if value.nil?

      case parameter['type']
      when 'String', 'Text', 'Datetime' then value.is_a?(String)
      when 'Boolean' then [true, false].include?(value)
      when 'Integer' then value.is_a?(Integer) && value.abs <= 9_007_199_254_740_991
      when 'Resource'
        output ? value.is_a?(Hash) && valid_json?(value) : value.is_a?(Integer) && value.abs <= 9_007_199_254_740_991
      when 'Float' then value.is_a?(Numeric) && value.finite?
      when 'Custom' then valid_json?(value) && (!query || (!value.is_a?(Hash) && !value.is_a?(Array)))
      else false
      end
    end

    def validate_object!(saved_io, live_io, object, input:, query: false)
      unsupported! unless object.is_a?(Hash)
      saved = (saved_io && saved_io.fetch('parameters', {})) || {}
      live = (live_io && live_io.fetch('parameters', {})) || {}
      object.each do |name, value|
        unsupported! unless compatible_parameter?(saved[name], live[name]) && valid_value?(saved[name], value, output: !input, query:)
      end
      return unless input

      [saved, live].each do |parameters|
        unsupported! if parameters.any? { |name, parameter| parameter['required'] == true && !object.has_key?(name) }
      end
    end

    def example(context)
      action = resolve(resource_path: context.resource_path, action_name: context.action_name)
      live = authorized_action(context)
      unsupported! unless action && live
      saved = saved_action(action)
      compatible_action!(action, saved, live, context)
      current = normalize(context.action)
      compatible_action!(action, saved, current, context)
      sample = normalize(context.sample)
      unsupported! unless sample.is_a?(Hash) && [true, false].include?(sample['status'])
      paths = sample['path_params'] || []
      unsupported! unless paths.is_a?(Array) && paths.length == action.fetch(:placeholders).length && paths.all? do |value|
        (value.is_a?(Integer) && value.abs <= 9_007_199_254_740_991) || (value.is_a?(String) && !value.empty? && !%w[. ..].include?(value))
      end
      input = sample['request'].nil? ? {} : sample['request']
      validate_object!(saved['input'], live['input'], input, input: true, query: %w[GET OPTIONS].include?(action.fetch(:method)))
      validate_object!(saved['input'], current['input'], input, input: true, query: %w[GET OPTIONS].include?(action.fetch(:method)))
      options = {}
      unless paths.empty?
        options['path'] = action.fetch(:placeholders).each_with_index.to_h { |name, index| [Naming.identifier(name), paths[index]] }
      end
      unless input.empty?
        fields = action.fetch(:input).fetch(:parameters)
        options['params'] = input.to_h { |name, value| [fields.find { |field| field[:wire_name] == name }.fetch(:emitted_name), value] }
      end
      response = sample['response']
      unless response.nil?
        values = action[:output] && action[:output][:layout].end_with?('_list') ? response : [response]
        unsupported! unless values.is_a?(Array)
        values.each do |value|
          validate_object!(saved['output'], live['output'], value, input: false)
          validate_object!(saved['output'], current['output'], value, input: false)
        end
      end
      members = (@accessors.fetch(action.fetch(:schema_path)) + [action.fetch(:accessor_name)]).map { |name| "[#{literal(name)}]" }.join
      call = "api#{members}"
      call += "(#{literal(options) unless options.empty?})"
      if sample['status'] == false || (sample['http_status'].is_a?(Integer) && sample['http_status'] >= 400)
        body = ['try {', "  await #{call};", '  throw new Error("Expected the documented request to fail");',
                '} catch (error) {', '  if (!(error instanceof AsyncError)) throw error;',
                '  void [error.kind, error.httpStatus, error.errors, error.envelope, error.response];', '}']
      else
        body = ["const result = await #{call};", 'void [result.data, result.meta, result.envelope, result.httpStatus];']
        body.concat(output_lines(action, response))
      end
      body << '// Request success does not establish completion of a server-side operation.' if action.fetch(:blocking)
      program(context, body, action_authentication(action, context))
    end

    def output_lines(action, response)
      return [] unless response && action[:output]

      list = action[:output][:layout].end_with?('_list')
      values = list ? response : [response]
      names = values.flat_map(&:keys).uniq
      body = names.flat_map do |name|
        expression = "item[#{literal(name)}]"
        ["const value#{names.index(name)}: unknown = #{expression};", "if (value#{names.index(name)} !== null && value#{names.index(name)} !== undefined) void value#{names.index(name)};"]
      end
      list ? ['for (const item of result.data) {'] + body.map { |line| "  #{line}" } + ['}'] : ['const item = result.data;'] + body
    end
  end
end
