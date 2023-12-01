require 'haveapi/client_example'

module HaveAPI::ClientExamples
  class PhpClient < HaveAPI::ClientExample
    label 'PHP'
    code :php
    order 20

    def init
      <<END
$api = new \\HaveAPI\\Client("#{base_url}", "#{version}");
END
    end

    def auth(method, desc)
      case method
      when :basic
        <<END
#{init}

$api->authenticate("basic", ["user" => "user", "password" => "secret"]);
END

      when :token
        <<END
#{init}

// Get token using username and password
$api->authenticate("token", [#{auth_token_credentials(desc).map { |k, v| "\"#{k}\" => \"#{v}\"" }.join(', ')}]);

echo "Token = ".$api->getAuthenticationProvider()->getToken();

// Next time, the client can authenticate using the token directly
$api->authenticate("token", ["token" => $savedToken]);
END

      when :oauth2
        '// OAuth2 is not supported by HaveAPI PHP client.'
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

      out << "// Throws exception \\HaveAPI\\Client\\Exception\\ActionFailed"
      out
    end

    def response(sample)
      out = "\n"

      case action[:output][:layout]
      when :hash
        out << "// $reply is an instance of \\HaveAPI\\Client\\Response\n"
        out << "// $reply->getResponse() returns an associative array of output parameters:\n"
        out << format_parameters(:output, sample[:response] || {}, "// ")

      when :hash_list
        out << "// $reply is an instance of \\HaveAPI\\Client\\Response\n"
        out << "// $reply->getResponse() returns an array of associative arrays:\n"

      when :object
        out << "// $reply is an instance of \\HaveAPI\\Client\\ResourceInstance\n"

        (sample[:response] || {}).each do |k, v|
          param = action[:output][:parameters][k]

          if param[:type] == 'Resource'
            out << "// $reply->#{k} = \\HaveAPI\\Client\\ResourceInstance("
            out << "resource: #{param[:resource].join('.')}, "

            if v.is_a?(::Hash)
              out << v.map { |k,v| "#{k}: #{PP.pp(v, '').strip}" }.join(', ')
            else
              out << "id: #{v}"
            end

            out << ")\n"

          elsif param[:type] == 'Custom'
            out << "// $reply->#{k} is a custom type"

          else
            out << "// $reply->#{k} = #{PP.pp(v, '')}"
          end
        end

      when :object_list
        out << "// $reply is an instance of \\HaveAPI\\Client\\ResourceInstanceList"
      end

      out
    end

    def format_parameters(dir, params, prefix = '')
      ret = []

      params.each do |k, v|
        if action[dir][:parameters][k][:type] == 'Custom'
          ret << "#{prefix}  \"#{k}\" => custom type}"

        else
          ret << "#{prefix}  \"#{k}\" => #{value(v)}"
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
