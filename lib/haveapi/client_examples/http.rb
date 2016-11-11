require 'pp'
require 'cgi'
require 'rack/utils'

module HaveAPI::ClientExamples
  class Http < HaveAPI::ClientExample
    label 'HTTP'
    code :http
    order 100

    def init

    end

    def auth(method, desc)
      case method
      when :basic
        <<END
GET / HTTP/1.1
Host: #{host}
Authorization: Basic dXNlcjpzZWNyZXQ=

END

      when :token
        <<END
POST /_auth/token/tokens HTTP/1.1
Host: #{host}
Content-Type: application/json

#{JSON.pretty_generate({token: {login: 'user', password: 'secret', lifetime: 'fixed'}})}
END
      end
    end

    def request(sample)
      path = resolve_path(
          action[:method],
          action[:url],
          sample[:url_params] || [],
          sample[:request]
      )

      req = "#{action[:method]} #{path} HTTP/1.1\n"
      req << "Host: #{host}\n"
      req << "Content-Type: application/json\n\n"

      if action[:method] != 'GET' && sample[:request] && !sample[:request].empty?
        req << JSON.pretty_generate({action[:input][:namespace] => sample[:request]})
      end

      req
    end

    def response(sample)
      content = JSON.pretty_generate({
          status: sample[:status],
          message: sample[:message],
          response: {action[:output][:namespace] => sample[:response]},
          errors: sample[:errors],
      })

      status_msg = Rack::Utils::HTTP_STATUS_CODES[sample[:http_status]]

      res = "HTTP/1.1 #{sample[:http_status]} #{status_msg}\n"
      res << "Content-Type: application/json;charset=utf-8\n"
      res << "Content-Length: #{content.size}\n\n"
      res << content
      res
    end

    def resolve_path(method, url, url_params, input_params)
      ret = url.clone

      url_params.each do |v|
        ret.sub!(/:[a-zA-Z\-_]+/, v.to_s)
      end

      return ret if method != 'GET' || !input_params || input_params.empty?

      ret << '?'
      ret << input_params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')

      ret
    end
  end
end
