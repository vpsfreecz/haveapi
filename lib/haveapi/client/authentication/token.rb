module HaveAPI::Client::Authentication
  class Token < Base
    register :token

    def setup
      @via = @opts[:via] || :header
      @token = @opts[:token]

      request_token unless @token

      @configured = true
    end

    def request_url_params
      return {} unless @configured
      check_validity
      @via == :query_param ? {@desc[:query_parameter] => @token} : {}
    end

    def request_headers
      return {} unless @configured
      check_validity
      @via == :header ? {@desc[:http_header] => @token} : {}
    end

    def save
      {token: @token}
    end

    def load(hash)
      @token = hash[:token]
    end

    protected
    def request_token
      a = HaveAPI::Client::Action.new(@communicator, :request, @desc[:resources][:token][:actions][:request], [])
      ret = a.execute({login: @opts[:user], password: @opts[:password], validity: @opts[:validity] || 300})

      raise AuthenticationFailed.new('bad username or password') unless ret[:status]

      @token = ret[:response][:token][:token]
      @valid_until = ret[:response][:token][:valid_until]
    end

    def check_validity

    end
  end
end
