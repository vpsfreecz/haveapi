module HaveAPI::ClientExamples
  class JsClient < HaveAPI::ClientExample
    label 'JavaScript'
    order 10

    def init
      <<END
import HaveAPI from 'haveapi-client'

var api = new HaveAPI.Client("#{base_url}");
END
    end

    def auth(method)
      case method
      when :basic
        <<END
#{init}

api.authenticate("basic", {
  username: "user",
  password: "secret"
}, function (client, status) {
  console.log("Authenticated?", status);
});
END

      when :token
        <<END
#{init}

// Request a new token
api.authenticate("token", {
  username: "user",
  password: "secret"
}, function (client, status) {
  console.log("Authenticated?", status);

  if (status)
    console.log("Token is", client.authProvider.token);
});

// Use an existing token
api.authenticate("token", {
  token: "qwertyuiop..."
}, function (client, status) {
  console.log("Authenticated?", status);
});
END
      end
    end

    def example(sample)
      args = []

      args.concat(sample[:url_params]) if sample[:url_params]

      if sample[:request] && !sample[:request].empty?
        args << JSON.pretty_generate(sample[:request])
      end

      out = "#{init}\n"
      out << "api.#{resource_path.join('.')}.#{action_name}"
      out << '('
      out << "#{args.join(', ')}, " unless args.empty?

      callback = <<END
function (client, response) {
  console.log('Response', response);
}
END
      out << callback.strip
      out << ');'
      out
    end
  end
end
