module HaveAPI::ClientExamples
  class JsClient < HaveAPI::ClientExample
    label 'JavaScript'
    code :javascript
    order 10

    def init
      <<END
import HaveAPI from 'haveapi-client'

var api = new HaveAPI.Client("#{base_url}");
END
    end

    def auth(method, desc)
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

      callback = "function (client, reply) {\n"
      callback << "  console.log('Response', reply);\n"

      if sample[:status]
        callback << response(sample)

      else
        callback << error(sample)
      end

      callback << "}"

      out << callback.strip
      out << ');'
      out
    end

    def response(sample)
      out = ''

      case action[:output][:layout]
      when :hash
        out << "# reply is an instance of HaveAPI.Client.Response\n"
        out << "# reply.response() returns an object with output parameters:\n"
        out << JSON.pretty_generate(sample[:response] || {}).split("\n").map do |v|
          "  // #{v}"
        end.join("\n")

      when :hash_list
        out << "# reply is an instance of HaveAPI.Client.Response\n"
        out << "# reply.response() returns an array of objects:\n"
        out << JSON.pretty_generate(sample[:response] || []).split("\n").map do |v|
          "  // #{v}"
        end.join("\n")

      when :object
        out << "  // reply is an instance of HaveAPI.Client.ResourceInstance\n"

        (sample[:response] || {}).each do |k, v|
          param = action[:output][:parameters][k]

          if param[:type] == 'Resource'
            out << "  // reply.#{k} = HaveAPI.Client.ResourceInstance("
            out << "resource: #{param[:resource].join('.')}, "

            if v.is_a?(::Hash)
              out << v.map { |k,v| "#{k}: #{PP.pp(v, '').strip}" }.join(', ')
            else
              out << "id: #{v}"
            end

            out << ")\n"

          elsif param[:type] == 'Custom' && (v.is_a?(::Hash) || v.is_a?(::Array))
            json = JSON.pretty_generate(v).split("\n").map do |v|
              "  // #{v}"
            end.join("\n")

            out << "  // reply.#{k} = #{json}"

          else
            out << "  // reply.#{k} = #{PP.pp(v, '')}"
          end
        end

      when :object_list
        out << "  // reply is an instance of HaveAPI.Client.ResourceInstanceList\n"
      end

      out

    end

    def error(sample)
      out = ''
      out << "  // reply.isOk() returns false\n"
      out << "  // reply.message() returns the error message\n"
      out << "  // reply.envelope.errors contains parameter errors\n"
      out
    end
  end
end
