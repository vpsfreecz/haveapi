module HaveAPI::Client::Authentication
  class Token < Base
    register :token
    attr_reader :token, :valid_to

    def setup
      @via = @opts[:via] || :header
      @token = @opts[:token]
      @valid_to = @opts[:valid_to]

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
      {token: @token, valid_to: @valid_to}
    end

    def load(hash)
      @token = hash[:token]
      @valid_to = hash[:valid_to]
    end

    protected
    def request_token
      a = HaveAPI::Client::Action.new(@communicator, :request, @desc[:resources][:token][:actions][:request], [])
      ret = a.execute({
                          login: @opts[:user],
                          password: @opts[:password],
                          lifetime: @opts[:lifetime],
                          interval: @opts[:interval] || 300})

      raise AuthenticationFailed.new('bad username or password') unless ret[:status]

      @token = ret[:response][:token][:token]

      @valid_to = ret[:response][:token][:valid_to]
      @valid_to = @valid_to && DateTime.iso8601(@valid_to).to_time
    end

    def check_validity
      if @valid_to && @valid_to < Time.now
        if @opts[:user] && @opts[:password]
          request_token
        else
          raise AuthenticationFailed.new('token expired')
        end
      end
    end
  end
end