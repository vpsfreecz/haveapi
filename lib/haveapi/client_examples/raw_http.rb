require 'pp'

module HaveAPI::ClientExamples
  class RawHttp < HaveAPI::ClientExample
    label 'HTTP'
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
      path = resolve_path(action[:url], sample[:url_params] || [])

      req = "#{action[:method]} #{path} HTTP/1.1\n"
      req << "Host: #{host}\n"
      req << "Content-Type: application/json\n\n"

      if sample[:request] && !sample[:request].empty?
        req << JSON.pretty_generate({action[:input][:namespace] => sample[:request]})
      end

      req
    end

    def resolve_path(url, params)
      ret = url.clone

      params.each do |v|
        ret.sub!(/:[a-zA-Z\-_]+/, v.to_s)
      end

      ret
    end
  end
end
