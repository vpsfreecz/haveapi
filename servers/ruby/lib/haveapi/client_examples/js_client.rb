require 'haveapi/client_examples/dynamic_helpers'

module HaveAPI::ClientExamples
  class JsClient < HaveAPI::ClientExample
    include DynamicHelpers

    label 'JavaScript (callback)'
    language 'javascript'
    language_label 'JavaScript'
    variant 'Callback'
    id 'javascript-callback'
    code :javascript
    order 10

    def asynchronous?
      false
    end

    def typescript?
      false
    end

    def js_literal(value)
      value = json_data(value)
      case value
      when Hash
        "{#{value.map { |key, entry| "[#{JSON.generate(key)}]: #{js_literal(entry)}" }.join(', ')}}"
      when Array
        "[#{value.map { |entry| js_literal(entry) }.join(', ')}]"
      when Integer
        raise Unsupported, 'This sample contains an integer outside JavaScript exact precision.' if value.abs > 9_007_199_254_740_991

        value.to_s
      else
        JSON.generate(value).gsub("\u2028", '\\u2028').gsub("\u2029", '\\u2029')
      end
    end

    def client_name
      asynchronous? ? 'AsyncClient' : 'CallbackClient'
    end

    def env_helper
      type = typescript? ? ': string' : ''
      <<~JS
        function credential(name#{type})#{type} {
          const value = env[name];
          if (value === undefined) throw new Error("Set " + name + " before running this example");
          return value;
        }
      JS
    end

    def program(body, authentication: nil)
      imports = "import { #{client_name}#{', AsyncError' if asynchronous? && thorough?} } from \"haveapi-client\";\n"
      imports << "import { env } from \"node:process\";\n\n#{env_helper}\n" if authentication
      declaration = "const api = new #{client_name}(#{js_literal(api_base)}, {version: #{js_literal(api_version)}});\n"
      unless thorough?
        return "#{imports}\n#{declaration}#{authentication || "await api.setup();\n"}#{body}" if asynchronous?

        return <<~JS
          #{imports}
          #{declaration}
          #{authentication || 'api.setup('}(api, ready) => {
            if (!ready) {
              console.error("Discovery or authentication failed");
              return;
            }
          #{indent(body)}});
        JS
      end

      if asynchronous?
        <<~JS
          #{imports}
          async function main()#{': Promise<void>' if typescript?} {
          #{indent(declaration)}  try {
          #{indent(authentication || "await api.setup();\n", 4)}#{indent(body, 4)}  } catch (error) {
              if (error instanceof AsyncError) {
                console.error(error.kind, error.message, error.errors);
              } else {
                throw error;
              }
            }
          }
          main().catch(error => console.error(error));
        JS
      else
        <<~JS
          #{imports}
          #{declaration}
          #{authentication || 'api.setup('}(api, ready) => {
            if (!ready) {
              console.error("Discovery or authentication failed");
              return;
            }
            try {
          #{indent(body, 4)}  } catch (error) {
              console.error(error);
            }
          });
        JS
      end
    end

    def init
      code_result { program(thorough? ? "console.log(\"Discovery complete\");\n" : '') }
    end

    def action_authentication
      return nil unless field(current_action, :auth)

      method = %i[token basic oauth2].find { |name| supported_auth?(name) }
      raise Unsupported, 'This action requires an authentication provider unsupported by this client.' unless method

      options = {
        token: '{token: credential("HAVEAPI_TOKEN")}',
        basic: '{user: credential("HAVEAPI_USER"), password: credential("HAVEAPI_PASSWORD")}',
        oauth2: '{access_token: {access_token: credential("HAVEAPI_ACCESS_TOKEN")}}'
      }.fetch(method)
      if asynchronous?
        "await api.authenticate(#{js_literal(method.to_s)}, #{options});\n"
      else
        "api.authenticate(#{js_literal(method.to_s)}, #{options}, "
      end
    end

    def auth(method, description)
      return limitation('This authentication provider is not advertised or supported by this client.') unless supported_auth?(method)

      code_result do
        options = case method.to_sym
                  when :basic
                    '{user: credential("HAVEAPI_USER"), password: credential("HAVEAPI_PASSWORD")}'
                  when :token
                    if token_login_fields(description).empty?
                      '{token: credential("HAVEAPI_TOKEN")}'
                    else
                      "env.HAVEAPI_TOKEN !== undefined ? {token: credential(\"HAVEAPI_TOKEN\")} : #{token_login_options(description)}"
                    end
                  when :oauth2
                    '{access_token: {access_token: credential("HAVEAPI_ACCESS_TOKEN")}}'
                  end
        authentication = if asynchronous?
                           "await api.authenticate(#{js_literal(method.to_s)}, #{options});\n"
                         else
                           "api.authenticate(#{js_literal(method.to_s)}, #{options}, "
                         end
        source = program(thorough? ? "console.log(\"Authenticated\");\n" : '', authentication:)
        if method.to_sym == :oauth2
          source = "// Use an existing access token; this client does not run an OAuth authorization flow.\n#{source}"
        elsif method.to_sym == :token && !token_login_fields(description).empty?
          source = "// Set HAVEAPI_TOKEN, or use login fields; HAVEAPI_AUTH_* and HAVEAPI_CHALLENGE_* contain JSON values.\n#{source}"
        end
        source
      end
    end

    def token_login_options(description)
      fields = token_login_fields(description).map do |name, _|
        "[#{js_literal(name.to_s)}]: JSON.parse(credential(#{js_literal("HAVEAPI_AUTH_#{name}")}))"
      end
      challenge = asynchronous? ? 'onChallenge' : 'callback'
      annotation = typescript? ? ': Record<string, unknown>' : ''
      fields << <<~JS.strip
        #{challenge}: (action, parameters) => {
          const input#{annotation} = Object.create(null);
          for (const name of Object.keys(parameters)) {
            if (name !== "token") input[name] = JSON.parse(credential("HAVEAPI_CHALLENGE_" + name));
          }
          return input;
        }
      JS
      "{#{fields.join(",\n")}}"
    end

    def example(sample)
      code_result do
        path, request = structured_sample(sample)
        if request.is_a?(Array)
          raise Unsupported, 'This JavaScript client accepts object input only; list input cannot be represented without dropping values.'
        end
        if !request.nil? && !request.is_a?(Hash)
          raise Unsupported, 'This JavaScript client requires object input.'
        end
        if !asynchronous? && field(field(current_action, :input), :parameters, {}).keys.any? { |name| %w[hasOwnProperty __proto__].include?(name.to_s) }
          raise Unsupported, 'This callback client cannot safely represent this input parameter name.'
        end
        if request && %w[GET OPTIONS].include?(field(current_action, :method).to_s.upcase) && request.values.any? { |value| value.is_a?(Hash) || value.is_a?(Array) }
          raise Unsupported, 'This JavaScript client cannot preserve nested values in query input.'
        end

        args = path.values.map { |value| js_literal(value) }
        if asynchronous?
          resource = current_resource_path.each_with_index.map do |name, index|
            "#{'api' if index == 0}.resource(#{js_literal(name)})"
          end.join
          options = request.nil? ? [] : ["{params: #{js_literal(request)}}"]
          body = "const result = await #{resource}.action(#{js_literal(current_action_name)})(#{(args + options).join(', ')});\n"
          body << "console.log(result.value);\n"
          body << "console.log(result.response.meta);\n" if thorough?
          if field(current_action, :blocking)
            body << "// Request success alone does not establish operation completion.\n"
            body << "const completed = await api.waitForCompletion(result, {timeoutMs: 300000});\nconsole.log(completed.state);\n"
          end
        else
          body = "const resource = CallbackClient.findResource(api, #{js_literal(current_resource_path)});\n"
          body << "const action = CallbackClient.findAction(resource, #{js_literal(current_action_name)});\n"
          options = request.nil? ? '' : "params: #{js_literal(request)},\n"
          options << <<~JS
            onReply: (owner, reply) => {
              if (!reply.isOk()) {
                console.error(reply.message(), reply.envelope.errors);
                return;
              }
              console.log(reply.response());
          JS
          options << "  console.log(reply.meta());\n" if thorough?
          options << "}\n"
          body << "action.directInvoke(#{(args + ["{\n#{indent(options)}}"]).join(', ')});\n"
          body << "// This prints the initial response; use its action-state metadata to monitor completion.\n" if field(current_action, :blocking)
        end
        authentication = action_authentication
        thorough? ? program(body, authentication:) : body
      end
    end
  end
end
