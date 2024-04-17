require 'haveapi/client_example'

module HaveAPI::ClientExamples
  class PhpClient < HaveAPI::ClientExample
    label 'PHP'
    code :php
    order 20

    def init
      <<~END
        $api = new \\HaveAPI\\Client("#{base_url}", "#{version}");
      END
    end

    def auth(method, desc)
      case method
      when :basic
        <<~END
          #{init}

          $api->authenticate("basic", ["user" => "user", "password" => "secret"]);
        END

      when :token
        <<~END
          #{init}

          // Get token using username and password
          $api->authenticate("token", [#{auth_token_credentials(desc).map { |k, v| "\"#{k}\" => \"#{v}\"" }.join(', ')}]);

          echo "Token = ".$api->getAuthenticationProvider()->getToken();

          // Next time, the client can authenticate using the token directly
          $api->authenticate("token", ["token" => $savedToken]);
        END

      when :oauth2
        <<~END
          // OAuth2 requires session
          session_start();

          // Client instance
          #{init}
          // Check if we already have an access token
          if (isset($_SESSION["access_token"])) {
            // We're already authenticated, reuse the existing access token
            $api->authenticate("oauth2", ["access_token" => $_SESSION["access_token"]]);

          } else {
            // Follow the OAuth2 authorization process to get an access token using
            // authorization code
            $api->authenticate("oauth2", [
              // Client id and secret are given by the API server
              "client_id" => "your client id",
              "client_secret" => "your client secret",

              // This example code should run on the URL below
              "redirect_uri" => "https://your-client.tld/oauth2-callback",

              // Scopes are specific to the API implementation
              "scope" => "all",
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
    end

    def example(sample)
      args = []

      args.concat(sample[:path_params]) if sample[:path_params]

      if sample[:request] && !sample[:request].empty?
        args << format_parameters(:input, sample[:request])
      end

      out = "#{init}\n"
      out << "$reply = $api->#{resource_path.join('->')}->#{action_name}"
      out << "(#{args.join(', ')});\n"

      return (out << response(sample)) if sample[:status]

      out << '// Throws exception \\HaveAPI\\Client\\Exception\\ActionFailed'
      out
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
        if action[dir][:parameters][k][:type] == 'Custom'
          "#{prefix}  \"#{k}\" => custom type}"
        else
          "#{prefix}  \"#{k}\" => #{value(v)}"
        end
      end

      "#{prefix}[\n#{ret.join(",\n")}\n#{prefix}]"
    end

    def value(v)
      return v if v.is_a?(::Numeric) || v === true || v === false

      "\"#{v}\""
    end
  end
end
