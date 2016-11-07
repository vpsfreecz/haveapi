require 'pp'

module HaveAPI::ClientExamples
  class RubyClient < HaveAPI::ClientExample
    label 'Ruby'
    code :ruby
    order 0

    def init
      <<END
require 'haveapi-client'

client = HaveAPI::Client::Client.new("#{base_url}")
END
    end

    def auth(method)
      case method
      when :basic
        <<END
#{init}

client.authenticate(:basic, username: "user", password: "secret")
END

      when :token
        <<END
#{init}

# Get token using username and password
client.authenticate(:token, username: "user", password: "secret")

puts "Token = \#{client.auth.token}"

# Next time, the client can authenticate using the token directly
client.authenticate(:token, token: saved_token)
END
      end
    end

    def example(sample)
      args = []

      args.concat(sample[:url_params]) if sample[:url_params]

      if sample[:request] && !sample[:request].empty?
        args << PP.pp(sample[:request], '').strip
      end

      out = "#{init}\n"
      out << "client.#{resource_path.join('.')}.#{action_name}"
      out << "(#{args.join(', ')})" unless args.empty?
      out
    end
  end
end
