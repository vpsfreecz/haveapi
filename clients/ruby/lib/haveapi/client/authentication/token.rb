require 'haveapi/client/authentication/base'

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

    def request_query_params
      return {} unless @configured

      check_validity
      @via == :query_param ? { @desc[:query_parameter] => @token } : {}
    end

    def request_headers
      return {} unless @configured

      check_validity
      @via == :header ? { @desc[:http_header] => @token } : {}
    end

    def save
      { token: @token, valid_to: @valid_to }
    end

    def load(hash)
      @token = hash[:token]
      @valid_to = hash[:valid_to]
    end

    def renew
      a = HaveAPI::Client::Action.new(
        nil,
        @communicator,
        :renew,
        @desc[:resources][:token][:actions][:renew],
        []
      )
      ret = HaveAPI::Client::Response.new(a, a.execute({}))
      raise HaveAPI::Client::ActionFailed, ret unless ret.ok?

      @valid_to = ret[:valid_to]
      @valid_to &&= DateTime.iso8601(@valid_to).to_time
    end

    def revoke
      a = HaveAPI::Client::Action.new(
        nil,
        @communicator,
        :revoke,
        @desc[:resources][:token][:actions][:revoke],
        []
      )
      ret = HaveAPI::Client::Response.new(a, a.execute({}))
      raise HaveAPI::Client::ActionFailed, ret unless ret.ok?
    end

    protected

    def request_token
      input = {
        lifetime: @opts[:lifetime],
        interval: @opts[:interval] || 300
      }
      request_credentials.each { |name| input[name] = @opts[name] if @opts[name] }

      cont, next_action, token = login_step(:request, input)
      return if cont == :done

      if @block.nil?
        raise AuthenticationFailed, 'implement multi-factor authentication'
      end

      loop do
        input = { token: }
        input.update(@block.call(next_action, auth_action_input(next_action)))

        cont, next_action, token = login_step(next_action, input)
        return if cont == :done
      end
    end

    def login_step(name, input)
      a = HaveAPI::Client::Action.new(
        nil,
        @communicator,
        name,
        @desc[:resources][:token][:actions][name],
        []
      )

      resp = HaveAPI::Client::Response.new(a, a.execute(input))

      if resp.failed?
        raise AuthenticationFailed, resp.message || 'invalid credentials'
      end

      if resp[:complete]
        @token = resp[:token]
        @valid_to = resp[:valid_to] && DateTime.iso8601(resp[:valid_to]).to_time
        :done
      else
        [:continue, resp[:next_action].to_sym, resp[:token]]
      end
    end

    def check_validity
      return unless @valid_to && @valid_to < Time.now && @opts[:user] && @opts[:password]

      request_token
    end

    def request_credentials
      @desc[:resources][:token][:actions][:request][:input][:parameters].each_key.reject do |name|
        %i[interval lifetime].include?(name)
      end
    end

    def auth_action_input(name)
      @desc[:resources][:token][:actions][name][:input][:parameters].except(:token)
    end
  end
end
