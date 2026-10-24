require 'haveapi/rust_client'
require 'date'

module HaveAPI::RustClient
  # Resolves the complete SDK model before checking a request's authorized help.
  class Documentation
    include Model

    class Unsupported < StandardError; end

    def self.from_description(description:, api_version:, protocol_version:, mount_path:,
                              crate_name:, crate_version: nil, source: nil)
      # Snapshot validation needs a structural origin; requests use context URLs.
      snapshot = Snapshot.from_description(
        description: JSON.parse(JSON.generate(description)), api_version:, protocol_version:, mount_path:,
        source_url: "https://haveapi.invalid#{mount_path}v#{api_version}/", profile: 'server-documentation'
      )
      from_snapshot(snapshot:, crate_name:, crate_version:, source:)
    end

    def self.from_snapshot(snapshot:, crate_name:, crate_version: nil, source: nil)
      new(snapshot:, crate_name:, crate_version:, source:)
    end

    def self.validate_source(source)
      return nil if source.nil?
      raise Error, 'invalid Rust SDK source' unless source.is_a?(Hash) && source.length == 2

      values = source.to_h { |key, value| [key.to_s, value] }
      url, revision = values.values_at('git', 'rev')
      unless values.keys.sort == %w[git rev] && url.is_a?(String) && !url.match?(/[\x00-\x20\x7f]/) &&
             revision.is_a?(String) && revision.match?(/\A[0-9a-fA-F]{40}\z/)
        raise Error, 'invalid Rust SDK source'
      end

      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTPS) && uri.host && !uri.host.empty? &&
             uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
        raise Error, 'invalid Rust SDK source'
      end

      values.transform_values { |value| value.dup.freeze }.freeze
    rescue URI::InvalidURIError
      raise Error, 'invalid Rust SDK source'
    end

    def initialize(snapshot:, config: nil, crate_name: nil, crate_version: nil, source: nil)
      if config
        raise Error, 'conflicting Rust SDK package settings' unless crate_name.nil? && crate_version.nil?

        config = JSON.parse(Snapshot.canonical(config))
        Generator.validate_config(config)
        crate_name, crate_version = config.values_at('crate_name', 'crate_version')
      end
      Model.validate_package(crate_name:, crate_version:)
      @crate_name = crate_name.dup
      @crate_version = crate_version&.dup
      @source = self.class.validate_source(source)
      @snapshot = Snapshot.validate(JSON.parse(Snapshot.canonical(snapshot)))
      @ir = IR.new(@snapshot)
      @import = @crate_name.tr('-', '_')
      raise Error, 'crate name cannot be imported in Rust' if %w[crate self super].include?(@import)

      @import = "r##{@import}" if Naming::RESERVED.include?(@import)
      @ir.actions.each { |action| meta_parameters(action) }
      freeze_data([@snapshot, @crate_name, @crate_version, @source, @import, @ir.resources, @ir.actions])
    end

    def resolve(resource_path:, action_name:)
      @ir.actions.find do |action|
        action[:resource][:path] == resource_path.map(&:to_s) && action[:name] == action_name.to_s
      end
    end

    def render(kind:, context:, mode:, auth_method: nil, auth_description: nil)
      unsupported!('Unsupported Rust execution mode.') unless %i[async blocking].include?(mode)
      unsupported!('The Rust SDK targets a different API version.') unless context.version.to_s == @snapshot['api_version']

      source = case kind
               when :init then program(context, mode, [])
               when :auth then authentication(context, mode, auth_method, auth_description)
               when :example then example(context, mode)
               else unsupported!('Unsupported Rust documentation section.')
               end
      { status: :code, code: source.freeze }.freeze
    rescue Unsupported => e
      { status: :limitation, reason: e.message.freeze }.freeze
    end

    private

    def unsupported!(reason)
      raise Unsupported, reason
    end

    def freeze_data(value, seen = {}.compare_by_identity)
      return if seen[value]

      seen[value] = true
      case value
      when Hash then value.each do |key, item|
        freeze_data(key, seen)
        freeze_data(item, seen)
      end
      when Array then value.each { |item| freeze_data(item, seen) }
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

    # Match normalize's last-insertion key semantics without visiting descendants.
    def normalized_members(value)
      value.is_a?(Hash) ? value.to_h { |key, item| [key.to_s, item] } : {}
    end

    def program(context, mode, body, credentials: [])
      dependencies = dependency_lines(mode)
      dependencies << '// cargo add tokio --features macros,rt-multi-thread' if mode == :async
      dependencies << '// cargo add serde_json'
      dependencies << '// Construct, use and drop this blocking client outside async runtime threads.' if mode == :blocking
      client = mode == :blocking ? "#{@import}::blocking::Client" : "#{@import}::Client"
      lines = dependencies + ["use #{client};", '']
      lines << '#[tokio::main]' if mode == :async
      lines << "#{'async ' if mode == :async}fn main() -> Result<(), Box<dyn std::error::Error>> {"
      lines << "    let base = std::env::var(\"HAVEAPI_BASE_URL\").unwrap_or_else(|_| #{literal(context.base_url)}.to_owned());"
      lines << '    let api = Client::builder(&base)'
      lines.concat(credentials.map { |line| "        #{line}" })
      lines << '        .build()?;'
      lines.concat((body.empty? ? ['let _ = &api;'] : body).map { |line| line.empty? ? '' : "    #{line}" })
      lines.push('    Ok(())', '}', '').join("\n")
    end

    def dependency_lines(mode)
      unless @source || @crate_version
        return ["// cargo add #{@crate_name}#{' --features blocking' if mode == :blocking}"]
      end

      fields = @source ? %w[git rev].map { |key| "#{key} = #{JSON.generate(@source.fetch(key))}" } : []
      fields << "version = #{JSON.generate(@crate_version)}" if @crate_version
      fields << 'features = ["blocking"]' if mode == :blocking
      ["// Cargo.toml: #{@crate_name} = { #{fields.join(', ')} }"]
    end

    def authentication(context, mode, method, description)
      provider = method.to_s
      providers = normalized_members(context.description)['authentication']
      live = normalized_members(providers)[provider]
      saved = @snapshot.fetch('description').fetch('authentication')[provider]
      unless live.is_a?(Hash) && saved
        unsupported!('This authentication provider is unavailable in the authorized Rust SDK profile.')
      end
      live = normalize(live)
      unsupported!('The authentication description differs from the authorized help.') unless normalize(description) == live

      credentials = case provider
                    when 'basic'
                      ['.basic_auth(std::env::var("HAVEAPI_USER")?, std::env::var("HAVEAPI_PASSWORD")?)']
                    when 'token', 'oauth2'
                      unless saved['http_header'] == live['http_header']
                        unsupported!('The Rust SDK authentication header differs from this API.')
                      end
                      setter = provider == 'token' ? 'token' : 'oauth2_token'
                      [".#{setter}(std::env::var(\"HAVEAPI_TOKEN\")?)"]
                    else unsupported!('This authentication provider is unsupported by the Rust client.')
                    end
      body = ['// Existing credentials only. Token acquisition and challenges require explicit advertised actions.',
              'let _ = &api;']
      program(context, mode, body, credentials:)
    end

    def example(context, mode)
      saved = resolve(resource_path: context.resource_path, action_name: context.action_name)
      live = authorized_action(context)
      unsupported!('This action is unavailable in the authorized Rust SDK profile.') unless saved && live
      sample = normalize(context.sample)
      unless sample.is_a?(Hash) && (%w[path_params request response errors].any? { |key| !sample[key].nil? } ||
                                    sample['status'] == false || (sample['http_status'] && sample['http_status'] != 200))
        unsupported!('This sample has no structured request or response to render.')
      end
      compatible_action!(saved, live, context)
      paths = sample['path_params'] || []
      unless paths.is_a?(Array) && paths.length == saved[:placeholders].length && paths.all? { |value| valid_path?(value) }
        unsupported!('The sample path arguments cannot be represented by this Rust SDK.')
      end
      inputs = input_lines(saved, live, sample['request'])
      validate_response!(saved, live, sample['response']) unless sample['response'].nil?
      bound = saved[:resource][:bound].length
      call = "api.#{saved[:resource][:module]}(#{paths.take(bound).map { |value| literal(value) }.join(', ')})"
      call << ".#{saved[:method]}(#{paths.drop(bound).map { |value| literal(value) }.join(', ')})"
      call << inputs.fetch(:chain)
      send = mode == :async ? '.send().await' : '.send()'
      body = inputs.fetch(:before)
      if sample['status'] == false || (sample['http_status'].is_a?(Integer) && sample['http_status'] >= 400)
        body += ["match #{call}#{send} {", '    Ok(_) => return Err("expected the documented request to fail".into()),',
                 '    Err(error) => {', '        let _ = error.http_status();',
                 '        // Inspect these explicitly; server diagnostics can contain sensitive values.',
                 '        let _ = (error.server_message(), error.validation_errors());', '    }', '}']
      else
        body += ["let response = #{call}#{send}?;", 'let _ = response.http_status;', 'let _ = &response.meta;']
        body.concat(output_lines(saved, sample['response']))
      end
      body << '// Request success or a timeout does not establish completion of a server-side operation.'
      body << '// Use only the separately documented action-state action; this SDK has no automatic wait helper.'
      program(context, mode, body, credentials: action_credentials(saved, context))
    end

    def action_credentials(action, context)
      return [] if action[:desc]['auth'] == false

      live = normalized_members(normalized_members(context.description)['authentication'])
      saved = @snapshot.fetch('description').fetch('authentication')
      if live.has_key?('basic') && saved.has_key?('basic')
        return ['.basic_auth(std::env::var("HAVEAPI_USER")?, std::env::var("HAVEAPI_PASSWORD")?)']
      end

      %w[token oauth2].each do |provider|
        advertised = live[provider]
        next unless advertised.is_a?(Hash) && saved[provider]
        next unless normalize(normalized_members(advertised)['http_header']) == saved[provider]['http_header']

        setter = provider == 'token' ? 'token' : 'oauth2_token'
        return [".#{setter}(std::env::var(\"HAVEAPI_TOKEN\")?)"]
      end
      unsupported!('This action requires authentication unavailable in the authorized Rust SDK profile.')
    end

    def authorized_action(context)
      resources = normalized_members(context.description)['resources']
      resource = nil
      context.resource_path.each do |name|
        resource = normalized_members(resources)[name.to_s]
        return nil unless resource.is_a?(Hash)

        resources = normalized_members(resource)['resources']
      end
      action = normalized_members(normalized_members(resource)['actions'])[context.action_name.to_s]
      normalize(action) if action.is_a?(Hash)
    end

    def compatible_action!(saved, live, context)
      mount = URI.parse(context.base_url).path
      mount = '/' if mount.empty?
      mount += '/' unless mount.end_with?('/')
      unless live['method'] == saved[:desc]['method'] && live['path'] == mount + saved[:route] &&
             (live['auth'] == false) == (saved[:desc]['auth'] == false)
        unsupported!('The Rust SDK route or HTTP method differs from this API action.')
      end
      %w[input output].each do |direction|
        saved_io = saved[direction.to_sym]
        live_io = live[direction]
        next if empty_io?(saved_io && saved_io[:desc]) && empty_io?(live_io)

        unless saved_io && live_io && saved_io[:desc]['layout'] == live_io['layout'] &&
               saved_io[:desc]['namespace'] == live_io['namespace'] && saved_io[:desc]['format'] == live_io['format']
          unsupported!('The Rust SDK input or output layout differs from this API action.')
        end
      end
      %i[global_input object_input].each do |key|
        next unless saved[key] && saved[key][:parameters].any? { |parameter| parameter[:desc]['required'] == true }

        unsupported!('This Rust SDK action requires metadata that is absent from the sample.')
      end
      %w[global object].each do |role|
        if live.dig('meta', role, 'input', 'parameters')&.any? { |_name, parameter| parameter['required'] == true }
          unsupported!('This action requires metadata that is absent from the sample.')
        end
      end
    end

    def empty_io?(io)
      io.nil? || io == { 'parameters' => {} }
    end

    def input_lines(saved, live, request)
      io = saved[:input]
      if io.nil?
        unsupported!('This Rust SDK action cannot represent the sample input.') unless request.nil? || request == {}
        return { before: [], chain: '' }
      end
      list = io[:layout].end_with?('_list')
      unsupported!('Rust GET requests do not support list input.') if list && saved[:desc]['method'] == 'GET'
      values = if request.nil?
                 list ? [] : {}
               else
                 request
               end
      unless list ? values.is_a?(Array) && values.all?(Hash) : values.is_a?(Hash)
        unsupported!('The sample input does not match the Rust SDK layout.')
      end
      objects = list ? values : [values]
      objects.each { |object| validate_object!(io, live['input'], object, required: true, method: saved[:desc]['method']) }
      return { before: [], chain: setter_chain(io, values) } unless list

      input = "#{@import}::resources::#{saved[:resource][:module]}::#{saved[:method]}::Input"
      lines = ['let input = vec![']
      objects.each do |object|
        lines << "    #{input} {"
        object.each do |name, value|
          parameter = io[:parameters].find { |item| item[:name] == name }
          value_code = value.nil? ? "#{@import}::InputValue::Null" : "#{@import}::InputValue::Value(#{typed_literal(parameter, value)})"
          lines << "        #{parameter[:field]}: #{value_code},"
        end
        lines << '        ..Default::default()'
        lines << '    },'
      end
      lines << '];'
      { before: lines, chain: '.input(input)' }
    end

    def validate_object!(saved_io, live_io, object, required:, method: nil)
      live_params = live_io && live_io.fetch('parameters', {})
      object.each do |name, value|
        parameter = saved_io[:parameters].find { |item| item[:name] == name }
        live_parameter = live_params && live_params[name]
        unless parameter && live_parameter && compatible_parameter?(parameter[:desc], live_parameter)
          unsupported!('A sample parameter is unavailable or has changed in this Rust SDK.')
        end
        unless valid_value?(parameter[:desc], value, output: !required)
          unsupported!('A sample value cannot be represented by this Rust SDK.')
        end
        if method == 'GET' && parameter[:desc]['type'] == 'Custom' && (value.is_a?(Hash) || value.is_a?(Array))
          unsupported!('Rust GET requests do not support nested Custom query values.')
        end
      end
      return unless required

      [saved_io[:desc].fetch('parameters'), live_params || {}].each do |parameters|
        if parameters.any? { |name, desc| desc['required'] == true && !object.has_key?(name) }
          unsupported!('The sample omits a required Rust SDK input.')
        end
      end
    end

    def compatible_parameter?(saved, live)
      %w[type resource value_id value_label].all? { |key| saved[key] == live[key] } &&
        %w[nullable required].all? { |key| (saved[key] == true) == (live[key] == true) }
    end

    def valid_value?(desc, value, output: false)
      return output || desc['nullable'] == true if value.nil?

      case desc['type']
      when 'String', 'Text' then value.is_a?(String)
      when 'Datetime' then value.is_a?(String) || value.is_a?(Time) || value.is_a?(DateTime)
      when 'Integer' then value.is_a?(Integer) && value.between?(-(2**63), (2**63) - 1)
      when 'Resource'
        output ? value.is_a?(Hash) : value.is_a?(Integer) && value.between?(0, (2**63) - 1)
      when 'Float' then value.is_a?(Numeric) && value.real? && value.finite? && value.to_f.finite?
      when 'Boolean' then [true, false].include?(value)
      when 'Custom' then json_value?(value)
      else false
      end
    end

    def json_value?(value)
      case value
      when Hash then value.all? { |key, item| key.is_a?(String) && json_value?(item) }
      when Array then value.all? { |item| json_value?(item) }
      when String, Integer, TrueClass, FalseClass, NilClass then true
      when Float then value.finite?
      else false
      end
    end

    def valid_path?(value)
      (value.is_a?(String) || value.is_a?(Integer)) && !value.to_s.empty? && !%w[. ..].include?(value.to_s)
    end

    def setter_chain(io, object)
      object.map do |name, value|
        parameter = io[:parameters].find { |item| item[:name] == name }
        value.nil? ? ".#{parameter[:field]}_null()" : ".#{parameter[:field]}(#{typed_literal(parameter, value)})"
      end.join
    end

    def typed_literal(parameter, value)
      case rust_type(parameter)
      when 'String' then "#{literal(value.respond_to?(:iso8601) ? value.iso8601 : value)}.to_owned()"
      when 'i64' then value == -(2**63) ? 'i64::MIN' : "#{value}_i64"
      when 'f64' then "#{value.to_f}_f64"
      when 'bool' then value.to_s
      when 'serde_json::Value' then "serde_json::from_str::<serde_json::Value>(#{literal(JSON.generate(value))})?"
      end
    end

    def validate_response!(saved, live, response)
      io = saved[:output]
      unless io
        unsupported!('The sample response does not match this Rust SDK.') unless response == {}
        return
      end
      list = io[:layout].end_with?('_list')
      unless list ? response.is_a?(Array) && response.all?(Hash) : response.is_a?(Hash)
        unsupported!('The sample response does not match this Rust SDK layout.')
      end
      (list ? response : [response]).each { |object| validate_object!(io, live['output'], object, required: false) }
    end

    def output_lines(action, response)
      return ['let _ = &response.output;'] unless action[:output] && response

      list = action[:output][:layout].end_with?('_list')
      names = (list ? response : [response]).flat_map(&:keys).uniq
      lines = list ? ['for item in &response.output {'] : []
      names.each do |name|
        parameter = action[:output][:parameters].find { |item| item[:name] == name }
        target = list ? 'item' : 'response.output'
        lines << "#{'    ' if list}let _ = &#{target}.#{parameter[:field]};"
      end
      lines << '}' if list
      lines
    end

    def literal(value)
      Naming.literal(value)
    end
  end
end
