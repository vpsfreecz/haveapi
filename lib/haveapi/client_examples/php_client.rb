module HaveAPI::ClientExamples
  class PhpClient < HaveAPI::ClientExample
    label 'PHP'
    order 20

    def init
      <<END
$api = new \\HaveAPI\\Client("#{base_url}");
END
    end

    def auth(method)
      case method
      when :basic
        <<END
#{init}

$api->authenticate("basic", ["username" => "user", "password" => "secret"]);
END

      when :token
        <<END
#{init}

# Get token using username and password
$api->authenticate("token", ["username" => "user", "password" => "secret"]);

echo "Token = ".$api->getAuthenticationProvider()->getToken();

# Next time, the client can authenticate using the token directly
$api->authenticate("token", ["token" => $savedToken]);
END
      end
    end

    def example(sample)
      args = []

      args.concat(sample[:url_params]) if sample[:url_params]

      if sample[:request] && !sample[:request].empty?
        args << input_parameters(sample[:request])
      end

      out = "#{init}\n"
      out << "$api->#{resource_path.join('->')}->#{action_name}"
      out << "(#{args.join(', ')});"
      out
    end

    def input_parameters(params)
      ret = []

      params.each do |k, v|
        ret << "  \"#{k}\" => #{value(v)}"
      end

      "[\n#{ret.join(",\n")}\n]"
    end

    def value(v)
      return v if v.is_a?(::Numeric) || v === true || v === false
      "\"#{v}\""
    end
  end
end
