require 'pp'
require 'cgi'

module HaveAPI::ClientExamples
  class Http < HaveAPI::ClientExample
    label 'HTTP'
    code :http
    order 100

    def init

    end

    def auth(method)
      case method
      when :basic
        <<END
GET / HTTP/1.1
Host: #{host}
Authorization: Basic dXNlcjpzZWNyZXQ=

END

      when :token
        <<END
POST /_auth/token HTTP/1.1
Host: #{host}
Content-Type: application/json

#{JSON.pretty_generate({token: {username: 'user', password: 'secret'}})}
END
      end
    end

    def example(sample)
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

      return req if sample[:response].nil? || sample[:response].empty?

      content = JSON.pretty_generate({
          action[:output][:namespace] => sample[:response]
      })

      req << "\n\n\n"
      req << "HTTP/1.1 200 OK\n"
      req << "Content-Type: application/json;charset=utf-8\n"
      req << "Content-Length: #{content.size}\n\n"
      req << content

      req
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
