require 'haveapi/client_examples/dynamic_helpers'

module HaveAPI::ClientExamples
  class PythonClient < HaveAPI::ClientExample
    include DynamicHelpers

    label 'Python (sync)'
    language 'python'
    language_label 'Python'
    variant 'Sync'
    id 'python-sync'
    code :python
    order 14

    def asynchronous?
      false
    end

    def python_literal(value)
      value = json_data(value)
      case value
      when Hash
        "{#{value.map { |key, entry| "#{JSON.generate(key)}: #{python_literal(entry)}" }.join(', ')}}"
      when Array
        "[#{value.map { |entry| python_literal(entry) }.join(', ')}]"
      when TrueClass then 'True'
      when FalseClass then 'False'
      when NilClass then 'None'
      else JSON.generate(value)
      end
    end

    def client_name
      asynchronous? ? 'AsyncClient' : 'Client'
    end

    def await_prefix
      asynchronous? ? 'await ' : ''
    end

    def program(body, imports: [], stdlib: [], auth: nil)
      package_imports = ([client_name] + (thorough? ? %w[ActionError HaveAPIError] : []) + imports).uniq.join(', ')
      source = (stdlib + (asynchronous? ? ['asyncio'] : [])).uniq.map { |name| "import #{name}\n" }.join
      source << "\nfrom haveapi_client import #{package_imports}\n\n\n"
      source << "async def main() -> None:\n" if asynchronous?
      level = asynchronous? ? 4 : 0
      if thorough?
        source << indent("try:\n", level)
        level += 4
      end
      options = ["version=#{python_literal(api_version)}"]
      options << "auth=#{auth}" if auth
      source << indent("#{'async ' if asynchronous?}with #{client_name}(#{python_literal(api_base)}, #{options.join(', ')}) as api:\n", level)
      source << indent(body, level + 4)
      if thorough?
        source << indent(<<~PY, level - 4)
          except ActionError as error:
              print(error.message, error.errors)
          except HaveAPIError as error:
              print(error.message, error.status_code)
        PY
      end
      source << "\n\nasyncio.run(main())\n" if asynchronous?
      source
    end

    def init
      code_result { program(thorough? ? "print(\"Discovery complete\")\n" : "# Call API actions inside this block.\npass\n") }
    end

    def auth(method, description)
      return limitation('This authentication provider is not advertised or supported by this client.') unless supported_auth?(method)

      code_result do
        body = thorough? ? "print(\"Authenticated\")\n" : "# Call API actions inside this block.\npass\n"
        case method.to_sym
        when :basic
          program(body, imports: ['BasicAuth'], stdlib: ['os'],
                        auth: 'BasicAuth(os.environ["HAVEAPI_USER"], os.environ["HAVEAPI_PASSWORD"])')
        when :oauth2
          source = program(body, imports: ['OAuth2Auth'], stdlib: ['os'],
                                 auth: 'OAuth2Auth(os.environ["HAVEAPI_ACCESS_TOKEN"])')
          "# Use an existing access token; OAuth acquisition and refresh are outside this client.\n#{source}"
        when :token
          fields = token_login_fields(description).merge(token_request_fields(description).select do |_, parameter|
            field(parameter, :required)
          end)
          if fields.empty?
            program(body, imports: ['TokenAuth'], stdlib: ['os'], auth: 'TokenAuth(os.environ["HAVEAPI_TOKEN"])')
          else
            challenge = asynchronous? ? 'AsyncAuthenticationChallenge' : 'AuthenticationChallenge'
            input = fields.map do |name, _|
              "#{python_literal(name.to_s)}: json.loads(os.environ[#{python_literal("HAVEAPI_AUTH_#{name}")}])"
            end.join(', ')
            body = <<~PY
              if "HAVEAPI_TOKEN" in os.environ:
                  #{await_prefix}api.set_auth(TokenAuth(os.environ["HAVEAPI_TOKEN"]))
              else:
                  # HAVEAPI_AUTH_* and HAVEAPI_CHALLENGE_* contain JSON values.
                  step = #{await_prefix}api.begin_token_login({#{input}})
                  while isinstance(step, #{challenge}):
                      values = {
                          name: json.loads(os.environ["HAVEAPI_CHALLENGE_" + name])
                          for name in step.input if name != "token"
                      }
                      step = #{await_prefix}step.submit(values)
            PY
            body << "print(\"Authenticated\")\n" if thorough?
            program(body, imports: ['TokenAuth', challenge], stdlib: %w[json os])
          end
        end
      end
    end

    def example(sample)
      code_result do
        path, request = structured_sample(sample)
        method = field(current_action, :method).to_s.upcase
        unless %w[GET POST PUT DELETE].include?(method)
          raise Unsupported, 'This Python client supports GET, POST, PUT and DELETE actions only.'
        end
        unless request.nil? || request.is_a?(Hash) || request.is_a?(Array)
          raise Unsupported, 'This Python client requires object or list input.'
        end
        if request.is_a?(Array) && field(field(current_action, :input), :namespace).to_s.empty?
          raise Unsupported, 'This Python client requires a namespace for list input.'
        end

        check_get_sample(request) if method == 'GET'

        resource = current_resource_path.each_with_index.map do |name, index|
          "#{'api' if index == 0}.resources[#{python_literal(name)}]"
        end.join
        arguments = []
        arguments << "path_params=#{python_literal(path)}" unless path.empty?
        arguments << "params=#{python_literal(request)}" unless request.nil?
        body = "response = #{await_prefix}#{resource}.actions[#{python_literal(current_action_name)}].call(#{arguments.join(', ')})\n"
        body << "print(response.data)\n"
        body << "print(response.meta)\n" if thorough?
        if field(current_action, :blocking)
          body << <<~PY
            # A request timeout does not cancel a server operation.
            if response.operation is not None:
                completed = #{await_prefix}response.operation.wait(timeout=300, interval=1)
                print(completed)
          PY
        end
        if field(current_action, :auth)
          method = %i[token basic oauth2].find { |name| supported_auth?(name) }
          raise Unsupported, 'This action requires an authentication provider unsupported by this client.' unless method

          provider, auth = {
            token: ['TokenAuth', 'TokenAuth(os.environ["HAVEAPI_TOKEN"])'],
            basic: ['BasicAuth', 'BasicAuth(os.environ["HAVEAPI_USER"], os.environ["HAVEAPI_PASSWORD"])'],
            oauth2: ['OAuth2Auth', 'OAuth2Auth(os.environ["HAVEAPI_ACCESS_TOKEN"])']
          }.fetch(method)
          if thorough?
            program(body, imports: [provider], stdlib: ['os'], auth:)
          else
            action_fragment(body)
          end
        else
          thorough? ? program(body) : action_fragment(body)
        end
      end
    end

    def action_fragment(body)
      asynchronous? ? "# Run inside an async function after initializing api.\n#{body}" : body
    end

    def check_get_sample(request)
      input = field(current_action, :input)
      namespace = field(input, :namespace)
      parameters = field(input, :parameters, {}).to_h { |name, parameter| [name.to_s, parameter] }
      safe_component = ->(value) { !value.to_s.empty? && !value.to_s.match?(/[\[\]]/) }
      safe_namespace = !namespace || safe_component.call(namespace)
      # Deliberately support a flat subset, leaving the full Rack encoder to the client.
      safe_request = request.nil? || (request.is_a?(Hash) && request.all? do |name, value|
        parameter = field(parameters, name)
        custom = field(parameter, :type) == 'Custom'
        scalar = !value.is_a?(Hash) && !value.is_a?(Array)
        custom_value = value.is_a?(String) || (value.nil? && field(parameter, :nullable))
        safe_component.call(name) && scalar && (!custom || custom_value)
      end)
      return if safe_namespace && safe_request

      raise Unsupported, 'Python GET examples support flat scalar input with bracket-free names; Custom values must be strings or nullable nulls.'
    end
  end
end
