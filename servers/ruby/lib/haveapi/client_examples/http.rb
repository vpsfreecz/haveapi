require 'pp'
require 'cgi'
require 'rack/utils'
require 'haveapi/client_example'

module HaveAPI::ClientExamples
  class Http < HaveAPI::ClientExample
    label 'HTTP'
    code :http
    order 100

    def init
      <<~END
        OPTIONS /v#{version}/ HTTP/1.1
        Host: #{host}

      END
    end

    def auth(method, desc)
      case method
      when :basic
        <<~END
          GET / HTTP/1.1
          Host: #{host}
          Authorization: Basic dXNlcjpzZWNyZXQ=

        END

      when :token
        login = auth_token_credentials(desc).merge(lifetime: 'fixed')

        <<~END
          POST /_auth/token/tokens HTTP/1.1
          Host: #{host}
          Content-Type: application/json

          #{JSON.pretty_generate({ token: login })}
        END

      when :oauth2
        <<~END
          # 1) Request authorization code
          GET #{desc[:authorize_path]}?response_type=code&client_id=$client_id&state=$state&redirect_uri=$client_redirect_uri HTTP/1.1
          Host: #{host}

          # 2) The user logs in using this API

          # 3) The API then redirects the user back to the client application
          GET $client_redirect_uri?code=$authorization_code&state=$state
          Host: client-application

          # 4) The client application requests access token
          POST #{desc[:token_path]}
          Content-Type: application/x-www-form-urlencoded

          grant_type=authorization_code&code=$authorization_code&redirect_uri=$client_redirect_uri&client_id=$client_id&client_secret=$client_secret
        END
      end
    end

    def request(sample)
      path = resolve_path(
        action[:method],
        action[:path],
        sample[:path_params] || [],
        sample[:request]
      )

      req = "#{action[:method]} #{path} HTTP/1.1\n"
      req << "Host: #{host}\n"
      req << "Content-Type: application/json\n\n"

      if action[:method] != 'GET' && sample[:request] && !sample[:request].empty?
        req << JSON.pretty_generate({ action[:input][:namespace] => sample[:request] })
      end

      req
    end

    def response(sample)
      content = JSON.pretty_generate({
          status: sample[:status],
          message: sample[:message],
          response: { action[:output][:namespace] => sample[:response] },
          errors: sample[:errors]
      })

      status_msg = Rack::Utils::HTTP_STATUS_CODES[sample[:http_status]]

      res = "HTTP/1.1 #{sample[:http_status]} #{status_msg}\n"
      res << "Content-Type: application/json;charset=utf-8\n"
      res << "Content-Length: #{content.size}\n\n"
      res << content
      res
    end

    def resolve_path(method, path, path_params, input_params)
      ret = path.clone

      path_params.each do |v|
        ret.sub!(/\{[a-zA-Z\-_]+\}/, v.to_s)
      end

      return ret if method != 'GET' || !input_params || input_params.empty?

      ret << '?'
      ret << input_params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')

      ret
    end
  end
end
