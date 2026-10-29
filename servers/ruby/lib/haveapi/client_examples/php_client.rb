require 'haveapi/client_example'

module HaveAPI::ClientExamples
  class PhpClient < HaveAPI::ClientExample
    label 'PHP'
    language 'php'
    language_label 'PHP'
    code :php
    order 20

    def self.detail_levels_for(_kind, context:, result:, auth_method: nil, auth_description: nil)
      result[:status] == :limitation ? SIMPLE_DETAIL_LEVELS : DEFAULT_DETAIL_LEVELS
    end

    def initialization
      "$api = new \\HaveAPI\\Client(#{value(base_url)}, #{value(version.to_s)});\n"
    end

    def with_error_handling(body)
      <<~PHP
        try {
        #{body.lines.map { |line| line == "\n" ? line : "    #{line}" }.join.chomp}
        } catch (\\HaveAPI\\Client\\Exception\\ValidationError $error) {
            echo $error->getMessage() . "\\n";
            print_r($error->getErrors());
        } catch (\\HaveAPI\\Client\\Exception\\ActionFailed $error) {
            echo $error->getMessage() . "\\n";
            print_r($error->getErrors());
        } catch (\\HaveAPI\\Client\\Exception\\Base $error) {
            echo $error->getMessage() . "\\n";
        } catch (\\Exception $error) {
            // Dependency failures still propagate to the application.
            echo $error->getMessage() . "\\n";
            throw $error;
        }
      PHP
    end

    def init
      thorough? ? with_error_handling("#{initialization}$api->setup();\n") : initialization
    end

    def auth_login_literal(name, parameter, value)
      return value unless value.nil?

      # Token::requestToken uses isset: false survives, explicit null does not.
      auth_literal(name, parameter, excluding: [nil])
    end

    def auth(method, desc)
      source = case method
               when :basic
                 <<~END
                   #{initialization.chomp}

                   $api->authenticate('basic', ['user' => 'user', 'password' => 'secret']);
                 END

               when :token
                 <<~END
                   #{initialization.chomp}

                   // Get token using username and password
                   $api->authenticate('token', #{token_options(desc)});

                   // Next time, the client can authenticate using the token directly
                   $api->authenticate('token', ['token' => 'example-token']);
                 END

               when :oauth2
                 <<~END
                   // OAuth2 requires session
                   session_start();

                   // Client instance
                   #{initialization}
                   // Check if we already have an access token
                   if (isset($_SESSION['access_token'])) {
                       // We're already authenticated, reuse the existing access token
                       $api->authenticate('oauth2', ['access_token' => $_SESSION['access_token']]);
                   } else {
                       // Follow the OAuth2 authorization process to get an access token using
                       // authorization code
                       $api->authenticate('oauth2', [
                           // Client id and secret are given by the API server
                           'client_id' => 'example-client',
                           'client_secret' => 'example-client-secret',

                           // This example code should run on the URL below
                           'redirect_uri' => 'https://your-client.tld/oauth2-callback',

                           // Scopes are specific to the API implementation
                           'scope' => 'all',
                       ]);

                       $provider = $api->getAuthenticationProvider();

                       // We don't have authorization code yet, request one
                       if (!isset($_GET['code'])) {
                           // Redirect the user to the authorization endpoint
                           $provider->requestAuthorizationCode();
                           exit;
                       } else {
                           // Request access token using the token endpoint
                           $provider->requestAccessToken();

                           // Store the access token in the session
                           $_SESSION['access_token'] = $provider->jsonSerialize();
                       }
                   }
                 END
               end
      return unless source

      source = source.sub(initialization, "#{initialization}$api->setup();\n") if thorough?
      thorough? ? with_error_handling(source) : source
    rescue HaveAPI::ClientExample::UnsupportedAuthentication => e
      { status: :limitation, reason: e.message }.freeze
    end

    def token_options(description)
      fields = auth_token_credentials(description).map { |name, item| "#{value(name)} => #{value(item)}" }
      continuations = auth_token_continuations(description)
      unless continuations.empty?
        fields << <<~PHP.strip
          'callback' => function ($action, $token, $parameters) {
              $continuations = #{value(continuations)};
              if (!array_key_exists($action, $continuations)) {
                  throw new \\InvalidArgumentException('Unknown authentication continuation');
              }
              $input = $continuations[$action];
              foreach (array_keys((array) $parameters) as $name) {
                  if ($name !== 'token' && !array_key_exists($name, $input)) {
                      throw new \\InvalidArgumentException('Unknown authentication input');
                  }
              }
              return $input;
          }
        PHP
      end
      return '[]' if fields.empty?

      "[\n#{fields.map { |field| field.lines.map { |line| "    #{line}" }.join.chomp }.join(",\n")}\n]"
    end

    def action_authentication
      return '' unless action[:auth] && context

      providers = auth_field(context.description, :authentication, {}).keys.map(&:to_s)
      return "$api->authenticate('token', ['token' => 'example-token']);" if providers.include?('token')
      return "$api->authenticate('basic', ['user' => 'user', 'password' => 'secret']);" if providers.include?('basic')
      return "$api->authenticate('oauth2', ['access_token' => ['access_token' => 'example-access-token']]);" if providers.include?('oauth2')

      raise HaveAPI::ClientExample::UnsupportedAuthentication, 'This action requires authentication unsupported by this client.'
    end

    def example(sample)
      credentials = action_authentication
      args = []

      args.concat(sample[:path_params]) if sample[:path_params]

      if sample[:request] && !sample[:request].empty?
        args << format_parameters(:input, sample[:request])
      end

      out = +''
      out << "$reply = $api->#{resource_path.join('->')}->#{action_name}"
      out << "(#{args.join(', ')});\n"

      out << if sample[:status]
               response(sample)
             else
               '// Throws exception \\HaveAPI\\Client\\Exception\\ActionFailed'
             end
      thorough? ? with_error_handling(["#{initialization}$api->setup();", credentials, out.chomp].reject(&:empty?).join("\n\n")) : out
    rescue HaveAPI::ClientExample::UnsupportedAuthentication => e
      { status: :limitation, reason: e.message }.freeze
    end

    def response(sample)
      out = "\n"

      case action[:output][:layout]
      when :hash
        out << "// $reply is an instance of \\HaveAPI\\Client\\Response\n"
        out << "// $reply->getResponse() returns an associative array of output parameters:\n"
        out << format_parameters(:output, sample[:response] || {}, '// ')

      when :hash_list
        out << "// $reply is an instance of \\HaveAPI\\Client\\Response\n"
        out << "// $reply->getResponse() returns an array of associative arrays:\n"

      when :object
        out << "// $reply is an instance of \\HaveAPI\\Client\\ResourceInstance\n"

        (sample[:response] || {}).each do |pn, pv|
          param = action[:output][:parameters][pn]

          if param[:type] == 'Resource'
            out << "// $reply->#{pn} = \\HaveAPI\\Client\\ResourceInstance("
            out << "resource: #{param[:resource].join('.')}, "

            out << if pv.is_a?(::Hash)
                     pv.map { |k, v| "#{k}: #{PP.pp(v, '').strip}" }.join(', ')
                   else
                     "id: #{pv}"
                   end

            out << ")\n"

          elsif param[:type] == 'Custom'
            out << "// $reply->#{pn} is a custom type"

          else
            out << "// $reply->#{pn} = #{PP.pp(pv, '')}"
          end
        end

      when :object_list
        out << '// $reply is an instance of \\HaveAPI\\Client\\ResourceInstanceList'
      end

      out
    end

    def format_parameters(dir, params, prefix = '')
      ret = params.map do |k, v|
        "#{prefix}    #{value(k.to_s)} => #{value(v)}"
      end

      "#{prefix}[\n#{ret.join(",\n")}\n#{prefix}]"
    end

    def value(v)
      case v
      when ::NilClass
        'null'
      when ::Numeric, true, false
        v.to_s
      when ::Array
        "[#{v.map { |item| value(item) }.join(', ')}]"
      when ::Hash
        "[#{v.map { |key, item| "#{value(key.to_s)} => #{value(item)}" }.join(', ')}]"
      else
        string = v.to_s
        if string.match?(/[\x00-\x1f\x7f]/)
          escaped = string.gsub(/[\\"$\x00-\x1f\x7f]/) do |char|
            char.ord < 32 || char.ord == 127 ? format('\\x%02x', char.ord) : "\\#{char}"
          end
          "\"#{escaped}\""
        else
          escaped = string.gsub(/[\\']/) { |char| "\\#{char}" }
          "'#{escaped}'"
        end
      end
    end
  end
end
