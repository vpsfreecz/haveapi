require 'shellwords'
require 'haveapi/client_examples/http'

module HaveAPI::ClientExamples
  class Curl < Http
    label 'curl'
    language 'curl'
    language_label 'curl'
    code :bash
    order 90

    def init
      "$ curl --request OPTIONS #{Shellwords.escape(version_url)}"
    end

    def auth(method, desc)
      case method
      when :basic
        <<~END
          # Password is asked on standard input
          $ curl --request OPTIONS \\
                 --user user \\
                 #{Shellwords.escape(base_url)}
          Password: secret

          # Password given on the command line
          $ curl --request OPTIONS \\
                 --user user:secret \\
                 #{Shellwords.escape(base_url)}
        END

      when :token
        login = auth_token_credentials(desc)

        <<~END
          # Acquire the token
          $ curl --request POST \\
                 --header 'Content-Type: application/json' \\
                 --data-binary #{Shellwords.escape(JSON.generate(token: login))} \\
                 #{Shellwords.escape(File.join(base_url, '_auth', 'token', 'tokens'))}

          # Use a previously acquired token
          $ curl --request OPTIONS \\
                 --header #{Shellwords.escape("#{desc[:http_header]}: example-token")} \\
                 #{Shellwords.escape(base_url)}
        END

      when :oauth2
        '# See RFC 6749 for authorization process and RFC 6750 for access token usage.'
      end
    rescue HaveAPI::ClientExample::UnsupportedAuthentication => e
      { status: :limitation, reason: e.message }.freeze
    end

    def request(sample)
      url = File.join(
        base_url,
        resolve_path(
          action[:method],
          action[:path],
          sample[:path_params] || [],
          sample[:request]
        )
      )

      data = format_data({
          action[:input][:namespace] => sample[:request]
      })

      <<~END
        $ curl --request #{Shellwords.escape(action[:method].to_s)} \\
               --data-binary #{data} \\
               #{Shellwords.escape(url)}
      END
    end

    def response(sample)
      JSON.pretty_generate({
          status: sample[:status],
          message: sample[:message],
          response: { action[:output][:namespace] => sample[:response] },
          errors: sample[:errors]
      })
    end

    def format_data(data)
      Shellwords.escape(JSON.generate(data))
    end
  end
end
