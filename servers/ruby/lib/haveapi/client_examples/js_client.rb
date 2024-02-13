require 'haveapi/client_example'

module HaveAPI::ClientExamples
  class JsClient < HaveAPI::ClientExample
    label 'JavaScript'
    code :javascript
    order 10

    def init
      <<~END
        import HaveAPI from 'haveapi-client'

        var api = new HaveAPI.Client("#{base_url}", {version: "#{version}"});
      END
    end

    def auth(method, desc)
      case method
      when :basic
        <<~END
          #{init}

          api.authenticate("basic", {
            user: "user",
            password: "secret"
          }, function (client, status) {
            console.log("Authenticated?", status);
          });
        END

      when :token
        <<~END
          #{init}

          // Request a new token
          api.authenticate("token", {
            #{auth_token_credentials(desc).map { |k, v| "#{k}: \"#{v}\"" }.join(",\n  ")}
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

      when :oauth2
        <<~END
          #{init}
          // The JavaScript client must be configured with OAuth2 access token, it does not
          // support the authorization procedure to obtain a new access token.
          var accessToken = {
            access_token: "the access token"
          };

          // The client is authenticated immediately, no need for a callback
          api.authenticate("oauth2", {access_token: accessToken});
        END
      end
    end

    def example(sample)
      args = []

      args.concat(sample[:path_params]) if sample[:path_params]

      if sample[:request] && !sample[:request].empty?
        args << JSON.pretty_generate(sample[:request])
      end

      out = "#{init}\n"
      out << "api.#{resource_path.join('.')}.#{action_name}"
      out << '('
      out << "#{args.join(', ')}, " unless args.empty?

      callback = "function (client, reply) {\n"
      callback << "  console.log('Response', reply);\n"

      callback << if sample[:status]
                    response(sample)

                  else
                    error(sample)
                  end

      callback << '}'

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

        (sample[:response] || {}).each do |pn, pv|
          param = action[:output][:parameters][pn]

          if param[:type] == 'Resource'
            out << "  // reply.#{pn} = HaveAPI.Client.ResourceInstance("
            out << "resource: #{param[:resource].join('.')}, "

            out << if pv.is_a?(::Hash)
                     pv.map { |k, v| "#{k}: #{PP.pp(v, '').strip}" }.join(', ')
                   else
                     "id: #{pv}"
                   end

            out << ")\n"

          elsif param[:type] == 'Custom' && (pv.is_a?(::Hash) || pv.is_a?(::Array))
            json = JSON.pretty_generate(pv).split("\n").map do |v|
              "  // #{v}"
            end.join("\n")

            out << "  // reply.#{pn} = #{json}"

          else
            out << "  // reply.#{pn} = #{PP.pp(pv, '')}"
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
