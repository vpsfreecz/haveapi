require 'pp'
require 'haveapi/client_example'

module HaveAPI::ClientExamples
  class RubyClient < HaveAPI::ClientExample
    label 'Ruby'
    code :ruby
    order 0

    def init
      <<~END
        require 'haveapi-client'

        client = HaveAPI::Client.new("#{base_url}", version: "#{version}")
      END
    end

    def auth(method, desc)
      case method
      when :basic
        <<~END
          #{init}

          client.authenticate(:basic, user: "user", password: "secret")
        END

      when :token
        <<~END
          #{init}

          # Get token using username and password
          client.authenticate(:token, #{auth_token_credentials(desc).map { |k, v| "#{k}: \"#{v}\"" }.join(', ')})

          puts "Token = \#{client.auth.token}"

          # Next time, the client can authenticate using the token directly
          client.authenticate(:token, token: saved_token)
        END

      when :oauth2
        '# OAuth2 is not supported by HaveAPI Ruby client.'
      end
    end

    def example(sample)
      args = []

      args.concat(sample[:path_params]) if sample[:path_params]

      if sample[:request] && !sample[:request].empty?
        args << PP.pp(sample[:request], '').strip
      end

      out = "#{init}\n"
      out << "reply = client.#{resource_path.join('.')}.#{action_name}"
      out << "(#{args.join(', ')})" unless args.empty?

      return (out << response(sample)) if sample[:status]

      out << "\n"
      out << '# Raises exception HaveAPI::Client::ActionFailed'
      out
    end

    def response(sample)
      out = "\n\n"

      case action[:output][:layout]
      when :hash
        out << "# reply is an instance of HaveAPI::Client::Response\n"
        out << "# reply.response() returns a hash of output parameters:\n"
        out << PP.pp(sample[:response] || {}, '').split("\n").map { |v| "# #{v}" }.join("\n")

      when :hash_list
        out << "# reply is an instance of HaveAPI::Client::Response\n"
        out << "# reply.response() returns an array of hashes:\n"
        out << PP.pp(sample[:response] || [], '').split("\n").map { |v| "# #{v}" }.join("\n")

      when :object
        out << "# reply is an instance of HaveAPI::Client::ResourceInstance\n"

        (sample[:response] || {}).each do |k, v|
          param = action[:output][:parameters][k]

          if param[:type] == 'Resource'
            out << "# reply.#{k} = HaveAPI::Client::ResourceInstance("
            out << "resource: #{param[:resource].join('.')}, "

            out << if v.is_a?(::Hash)
                     v.map { |k, v| "#{k}: #{PP.pp(v, '').strip}" }.join(', ')
                   else
                     "id: #{v}"
                   end

            out << ")\n"

          else
            out << "# reply.#{k} = #{PP.pp(v, '')}"
          end
        end

      when :object_list
        out << "# reply is an instance of HaveAPI::Client::ResourceInstanceList,\n"
        out << '# which is a subclass of Array'
      end

      out
    end
  end
end
