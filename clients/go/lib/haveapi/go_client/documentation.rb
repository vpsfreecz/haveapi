require 'json'
require 'uri'
require 'haveapi/go_client'
require 'haveapi/go_client/utils'

module HaveAPI::GoClient
  # Pure adapter over a complete description matching the configured SDK.
  # Never reconstruct names from a user's reduced documentation description.
  class Documentation
    include Utils

    Resolved = Struct.new(:resource, :action, :description)
    INPUT_LAYOUTS = %w[hash object].freeze
    OUTPUT_LAYOUTS = %w[hash object hash_list object_list].freeze
    PARAMETER_CONTRACT = %i[type nullable resource value_id value_label].freeze
    INPUT_MEMBERS = %w[SelectParameters UnselectParameters AnySelected].freeze

    def initialize(description:, import_path:, module_version: nil)
      unless import_path.is_a?(String) && import_path.match?(%r{\A[A-Za-z0-9][A-Za-z0-9._~/-]*\z}) \
          && import_path.split('/').none? { |part| ['', '.', '..'].include?(part) } \
          && (module_version.nil? || (module_version.is_a?(String) && module_version.match?(/\Av\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/)))
        raise ArgumentError, 'invalid Go SDK import path or module version'
      end

      @import_path = import_path.dup.freeze
      @module_version = module_version&.dup&.freeze
      @description = copy(description)
      validate_description
      @api = ApiVersion.new(@description)
      freeze_data(@description)
      freeze
    rescue KeyError, NoMethodError, TypeError
      raise ArgumentError, 'invalid saved Go SDK description'
    end

    def resolve(resource_path:, action_name:)
      parent = @api
      desc = @description
      resource_path.each do |name|
        parent = parent.resources.find { |resource| resource.name == name.to_s }
        return nil unless parent

        desc = lookup(desc[:resources], name)
      end
      return nil unless parent.is_a?(Resource)

      action = parent.actions.find { |item| item.name == action_name.to_s }
      unless action
        aliases = parent.actions.select { |item| item.aliases.map(&:to_s).include?(action_name.to_s) }
        action = aliases.first if aliases.one?
      end
      return unless action

      Resolved.new(resource: parent, action:, description: lookup(desc[:actions], action.name)).freeze
    end

    def render(kind:, context:, mode:, auth_method: nil, auth_description: nil)
      return limitation('This Go SDK example mode is unsupported.') unless mode == :sync

      case kind
      when :init
        code(program(context, [], ['_ = api']))
      when :auth
        render_auth(context, auth_method, auth_description)
      when :example
        render_example(context)
      else
        limitation('This Go SDK example is unavailable.')
      end
    rescue Unsupported => e
      limitation(e.message)
    end

    protected

    class Unsupported < StandardError; end

    def validate_description
      unless @description.is_a?(Hash) && @description[:authentication].is_a?(Hash) \
          && @description[:meta].is_a?(Hash) && [String, Symbol].any? { |type| @description[:meta][:namespace].is_a?(type) }
        raise ArgumentError, 'invalid saved Go SDK description'
      end

      validate_resources(@description[:resources])
    end

    def validate_resources(resources)
      raise ArgumentError, 'invalid saved Go SDK resources' unless resources.is_a?(Hash)

      resources.each_value do |resource|
        unless resource.is_a?(Hash) && resource[:actions].is_a?(Hash)
          raise ArgumentError, 'invalid saved Go SDK resources'
        end

        validate_resources(resource[:resources])
        resource[:actions].each_value do |action|
          unless action.is_a?(Hash) && action[:aliases].is_a?(Array) \
              && action[:aliases].all?(String) \
              && action[:method].is_a?(String) && %w[GET POST PUT PATCH DELETE HEAD OPTIONS].include?(action[:method]) \
              && action[:path].is_a?(String) && action[:path].start_with?('/') && !action[:path].start_with?('//') \
              && action[:meta].is_a?(Hash)
            raise ArgumentError, 'invalid saved Go SDK action'
          end

          %i[input output].each do |direction|
            io = action[direction]
            unless io.nil? || (io.is_a?(Hash) && io[:parameters].is_a?(Hash))
              raise ArgumentError, 'invalid saved Go SDK parameters'
            end
          end
        end
      end
    end

    def render_example(context)
      resolved = resolve(resource_path: context.resource_path, action_name: context.action_name)
      live = visible_action(context.description, context.resource_path, context.action_name)
      unsupported!('This action is unavailable in the configured Go SDK.') unless resolved && live && context.action
      saved = resolved.description
      check_action(saved, live)
      check_action(saved, context.action)
      sample = context.sample
      unless sample.is_a?(Hash) && [true, false].include?(sample[:status])
        unsupported!('This sample does not describe a structured request and response.')
      end

      action = resolved.action
      check_input(action, saved[:input])
      check_output(action, saved[:output], live[:output], sample, context)
      members = resolved.resource.resource_path.map(&:go_member_name) + [action.go_member_name]
      lines = ["invocation := api.#{members.join('.')}.Prepare()"]
      lines.concat(path_lines(action, sample))
      lines.concat(input_lines(action, saved[:input], live[:input], sample))
      lines.concat(metadata_lines(action, saved, live))
      lines.concat(call_lines(action, live, sample, context))
      code(program(context, ['fmt'], lines))
    end

    def check_action(saved, live)
      unless saved[:method] == live[:method] && saved[:path] == live[:path] \
          && (saved[:blocking] == true) == (live[:blocking] == true)
        unsupported!('The configured Go SDK does not match this action route.')
      end
      %i[input output].each do |direction|
        left = saved[direction] || {}
        right = live[direction] || {}
        unless left[:layout].to_s == right[:layout].to_s && left[:namespace].to_s == right[:namespace].to_s
          unsupported!('The configured Go SDK does not match this action layout.')
        end
      end
      return unless [saved, live].any? { |description| required_metadata?(description) }

      unsupported!('This action requires metadata that is absent from the sample.')
    end

    def required_metadata?(description)
      %i[global object].any? do |role|
        parameters = description.dig(:meta, role, :input, :parameters) || {}
        parameters.any? { |_name, parameter| parameter[:required] == true }
      end
    end

    def check_input(action, desc)
      return if !desc || (desc[:parameters] || {}).empty?

      unless INPUT_LAYOUTS.include?(desc[:layout].to_s)
        unsupported!('The Go generator does not support list input in documentation examples.')
      end
      check_parameters(action.input, desc, input: true)
    end

    def check_output(action, desc, live, sample, context)
      if !desc || (desc[:parameters] || {}).empty?
        if sample[:status] && sample[:response] && ![{}, []].include?(sample[:response])
          unsupported!('This response is unavailable in the configured Go SDK.')
        end
        return
      end

      unless OUTPUT_LAYOUTS.include?(desc[:layout].to_s)
        unsupported!('The Go generator does not support this output layout.')
      end
      check_parameters(action.output, desc, input: false)
      return unless sample[:status] && sample.has_key?(:response) && !sample[:response].nil?

      values = desc[:layout].to_s.end_with?('_list') ? sample[:response] : [sample[:response]]
      unsupported!('This sample does not match the Go SDK output layout.') unless values.is_a?(Array)
      values.each { |value| check_output_value(action.output, desc, live, value, context) }
    end

    def check_parameters(io, desc, input:)
      names = io ? io.parameters.map(&:name) : []
      unless (desc[:parameters] || {}).keys.all? { |name| names.include?(name.to_s) }
        unsupported!('The Go generator does not support Custom fields in this sample.')
      end
      members = io.parameters.map(&:go_name)
      reserved = input ? INPUT_MEMBERS + members.map { |name| "Set#{name}" } + members.map { |name| "Set#{name}Nil" } : []
      return unless members.uniq != members || members.intersect?(reserved)

      unsupported!('The Go generator cannot represent these parameter name collisions.')
    end

    def check_output_value(io, desc, live, value, context)
      unsupported!('This sample does not match the Go SDK output layout.') unless value.is_a?(Hash)
      value.each do |name, item|
        parameter = io.parameters.find { |candidate| candidate.name == name.to_s }
        unsupported!('This response field is unavailable in the configured Go SDK.') unless parameter
        left = lookup(desc[:parameters], name)
        right = lookup(live && live[:parameters], name)
        unless left && right && parameter_contract(left) == parameter_contract(right)
          unsupported!('This response field does not match the configured Go SDK.')
        end
        if item.nil? && !parameter.respond_to?(:association)
          unsupported!('The Go SDK cannot distinguish scalar null output from its zero value.')
        end
        literal(parameter.go_out_type, item) unless parameter.respond_to?(:association)
        next unless parameter.respond_to?(:association)
        next if item.nil?

        unless item.is_a?(Hash)
          unsupported!('The Go SDK requires an object for an associated response field.')
        end

        associated = parameter.association.resource.actions.find { |candidate| candidate.name == 'show' }
        path = parameter.association.resource.resource_path.map(&:name)
        saved_association = resolve(resource_path: path, action_name: 'show')
        live_association = visible_action(context.description, path, 'show')
        unless saved_association && live_association
          unsupported!('This associated response is unavailable in the visible Go SDK documentation.')
        end
        check_parameters(associated.output, saved_association.description[:output], input: false)
        check_output_value(associated.output, saved_association.description[:output], live_association[:output], item, context)
      end
    end

    def path_lines(action, sample)
      names = action.path.scan(/\{([a-zA-Z0-9\-_]+)\}/).flatten
      values = sample[:path_params] || []
      unless values.is_a?(Array) && names.length == values.length
        unsupported!('This sample does not supply all Go SDK path parameters.')
      end
      names.zip(values).map do |name, value|
        case value
        when Integer
          unsupported!('This path value is outside the Go int64 range.') unless int64?(value)
          "invocation.SetPathParamInt(#{go_string_literal(name)}, #{value})"
        when String
          "invocation.SetPathParamString(#{go_string_literal(name)}, #{go_string_literal(value)})"
        else
          unsupported!('This Go SDK path parameter must be an integer or string.')
        end
      end
    end

    def input_lines(action, saved, live, sample)
      return [] unless sample.has_key?(:request) && !sample[:request].nil?

      request = sample[:request]
      unsupported!('The Go generator supports object input only.') unless request.is_a?(Hash)
      unless action.has_input?
        unsupported!('This input is unavailable in the configured Go SDK.') unless request.empty?
        return []
      end
      lines = ["#{'input := ' unless request.empty?}invocation.NewInput().SelectParameters()"]
      request.each do |name, value|
        parameter = action.input.parameters.find { |candidate| candidate.name == name.to_s }
        saved_parameter = lookup(saved && saved[:parameters], name)
        live_parameter = lookup(live && live[:parameters], name)
        unless parameter && saved_parameter && live_parameter && parameter_contract(saved_parameter) == parameter_contract(live_parameter)
          unsupported!('This input field does not match the configured Go SDK.')
        end
        if value.nil?
          unsupported!('This Go SDK input field does not accept null.') unless parameter.nillable?
          lines << "input.Set#{parameter.go_name}Nil(true)"
        else
          lines << "input.Set#{parameter.go_name}(#{literal(parameter.go_in_type, value)})"
        end
      end
      lines
    end

    def metadata_lines(action, saved, live)
      io = action.metadata && action.metadata.global && action.metadata.global.input
      return [] unless io && io.parameters.any?

      saved_meta = saved.dig(:meta, :global, :input, :parameters) || {}
      live_meta = live.dig(:meta, :global, :input, :parameters) || {}
      return [] unless io.parameters.all? do |parameter|
        left = lookup(saved_meta, parameter.name)
        right = lookup(live_meta, parameter.name)
        left && right && parameter_contract(left) == parameter_contract(right)
      end

      ['// To supply advertised global metadata, select only the fields you set:',
       '// metadata := invocation.NewMetaInput().SelectParameters()'] +
        io.parameters.map { |parameter| "// metadata.Set#{parameter.go_name}(value) // value has type #{parameter.go_in_type}" }
    end

    def call_lines(action, live, sample, context)
      lines = [
        'response, err := invocation.Call()',
        'if err != nil {',
        '  fmt.Println(err)',
        '  return',
        '}',
        'if !response.Status {',
        '  fmt.Println(response.Message, response.Errors)',
        '  return',
        '}'
      ]
      return lines + ['// This sample demonstrates the failure branch above.'] unless sample[:status]

      lines.concat(output_lines(action, sample))
      if operation_visible?(action, live, context)
        lines.push(
          'if response.IsBlocking() {',
          '  state, err := response.OperationStatus()',
          '  if err != nil {',
          '    fmt.Println(err)',
          '    return',
          '  }',
          '  if !state.Status {',
          '    fmt.Println(state.Message, state.Errors)',
          '    return',
          '  }',
          '  // Inspect the operation status using its documented output fields.',
          '}',
          '// Request success does not establish operation completion.'
        )
      elsif action.blocking?
        lines << '// Request success does not establish operation completion.'
      end
      lines
    end

    def output_lines(action, sample)
      return [] unless action.has_output? && sample.has_key?(:response) && !sample[:response].nil?

      value = sample[:response]
      if action.output.layout.to_s.end_with?('_list')
        return ['fmt.Println(len(response.Output))'] if value.empty?

        # Choose fields present in every documented row, without fabricating a row.
        common = common_output_fields(action.output, value)
        return ['fmt.Println(len(response.Output))'] if common.empty?

        ['for _, item := range response.Output {', '  if item != nil {'] +
          output_fields(action.output, common, 'item').map { |line| "    #{line}" } + ['  }', '}']
      else
        ['if response.Output != nil {'] + output_fields(action.output, value, 'response.Output').map { |line| "  #{line}" } + ['}']
      end
    end

    def common_output_fields(io, rows)
      rows.first.each_with_object({}) do |(name, value), common|
        next unless rows.all? { |row| row.has_key?(name) }

        parameter = io.parameters.find { |candidate| candidate.name == name.to_s }
        if parameter.respond_to?(:association)
          values = rows.map { |row| row[name] }
          if values.all?(Hash)
            associated = parameter.association.resource.actions.find { |candidate| candidate.name == 'show' }
            common[name] = common_output_fields(associated.output, values)
          elsif values.all?(&:nil?)
            common[name] = nil
          end
        else
          common[name] = value
        end
      end
    end

    def output_fields(io, sample, variable)
      sample.flat_map do |name, value|
        parameter = io.parameters.find { |candidate| candidate.name == name.to_s }
        field = "#{variable}.#{parameter.go_name}"
        if parameter.respond_to?(:association) && value.is_a?(Hash)
          associated = parameter.association.resource.actions.find { |candidate| candidate.name == 'show' }
          ["if #{field} != nil {"] + output_fields(associated.output, value, field).map { |line| "  #{line}" } + ['}']
        else
          ["fmt.Println(#{field}#{' == nil' if value.nil?})"]
        end
      end
    end

    def operation_visible?(action, live, context)
      return false unless action.blocking?

      visible_id = live.dig(:meta, :global, :output, :parameters, :action_state_id)
      metadata = action.metadata && action.metadata.global && action.metadata.global.output
      saved_id = metadata && metadata.parameters.find { |parameter| parameter.name == 'action_state_id' }
      return false unless visible_id && visible_id[:type] == 'Integer' && saved_id && saved_id.go_out_type == 'int64'

      # Generated operation helpers currently use these exact members/types.
      state = resolve(resource_path: ['action_state'], action_name: 'show')
      visible_state = visible_action(context.description, ['action_state'], 'show')
      state && visible_state && state.resource.go_member_name == 'ActionState' && state.action.go_member_name == 'Show' \
        && state.action.go_response_type == 'ActionActionStateShowResponse' \
        && state.action.path.scan(/\{([a-zA-Z0-9\-_]+)\}/).flatten == ['action_state_id'] \
        && !state.action.has_input? \
        && state.description[:path] == visible_state[:path] && state.description[:method] == visible_state[:method] \
        && @description.dig(:meta, :namespace).to_s == context.description.dig(:meta, :namespace).to_s
    end

    def render_auth(context, method, desc)
      method = method.to_sym
      visible = lookup(context.description[:authentication], method)
      saved = lookup(@description[:authentication], method)
      unsupported!('This authentication method is unavailable in the configured Go SDK.') unless visible && saved && desc
      lines = case method
              when :basic
                ['api.SetBasicAuthentication(os.Getenv("HAVEAPI_USER"), os.Getenv("HAVEAPI_PASSWORD"))']
              when :token
                unless same_transport_name?(saved[:http_header], visible[:http_header]) &&
                       same_transport_name?(saved[:query_parameter], visible[:query_parameter])
                  unsupported!('This authentication method does not match the configured Go SDK.')
                end
                ['api.SetExistingTokenAuth(os.Getenv("HAVEAPI_TOKEN"))',
                 '// Use a token obtained through the advertised authentication provider.']
              when :oauth2
                unless saved[:http_header] == visible[:http_header]
                  unsupported!('This authentication method does not match the configured Go SDK.')
                end
                ['api.SetExistingOAuth2Auth(os.Getenv("HAVEAPI_ACCESS_TOKEN"))',
                 '// Obtain the access token through the OAuth2 provider before running this program.']
              else
                unsupported!('This authentication method is unsupported by the Go generator.')
              end
      code(program(context, ['os'], lines))
    end

    def same_transport_name?(saved, visible)
      # Automatic profiles copy Symbol names through JSON as Strings.
      [saved, visible].all? { |name| name.is_a?(String) || name.is_a?(Symbol) } && saved.to_s == visible.to_s
    end

    def program(context, imports, lines)
      # Saved server routes already include the mount root and /vVERSION.
      origin = URI.parse(context.base_url)
      origin.path = ''
      origin.query = origin.fragment = nil
      header = ["// go get #{@import_path}@#{@module_version || 'latest'}", 'package main', '', 'import (']
      imports.each { |name| header << "  #{go_string_literal(name)}" }
      header << "  client #{go_string_literal(@import_path)}"
      header.push(')', '', 'func main() {', "  api := client.New(#{go_string_literal(origin.to_s)})")
      (header + lines.map { |line| "  #{line}" } + ['}', '']).join("\n")
    end

    def literal(type, value)
      valid = case type
              when 'string' then value.is_a?(String)
              when 'int64' then int64?(value)
              when 'float64' then (value.is_a?(Float) || int64?(value)) && value.to_f.finite?
              when 'bool' then [true, false].include?(value)
              else false
              end
      unsupported!('This sample value cannot be represented by the Go SDK field type.') unless valid
      type == 'string' ? go_string_literal(value) : value.to_s
    end

    def int64?(value)
      value.is_a?(Integer) && value.between?(-(2**63), (2**63) - 1)
    end

    def parameter_contract(desc)
      PARAMETER_CONTRACT.map do |key|
        value = desc[key]
        if %i[value_id value_label].include?(key) && (value.is_a?(String) || value.is_a?(Symbol))
          value.to_s
        else
          value
        end
      end
    end

    def visible_action(description, path, name)
      desc = description
      path.each do |component|
        desc = lookup(desc[:resources], component)
        return nil unless desc
      end
      lookup(desc[:actions], name)
    end

    def lookup(hash, key)
      hash && (hash[key] || hash[key.to_s] || hash[key.to_s.to_sym])
    end

    def copy(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), result|
          unless (key.is_a?(String) || key.is_a?(Symbol)) && !result.has_key?(key.to_sym)
            raise ArgumentError, 'invalid saved Go SDK description'
          end

          result[key.to_sym] = copy(item)
        end
      when Array then value.map { |item| copy(item) }
      when String then value.dup
      when NilClass, Numeric, TrueClass, FalseClass, Symbol then value
      else raise ArgumentError, 'invalid saved Go SDK description'
      end
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

    def unsupported!(reason)
      raise Unsupported, reason
    end

    def code(source)
      { status: :code, code: source.freeze }.freeze
    end

    def limitation(reason)
      { status: :limitation, reason: reason.freeze }.freeze
    end
  end
end
