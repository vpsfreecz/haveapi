require 'haveapi/cli/authentication/base'
require 'haveapi/cli/utils'

module HaveAPI::CLI::Authentication
  class Token < Base
    register :token

    include HaveAPI::CLI::Utils

    def options(opts)
      @credentials = {}

      request_credentials.each do |name, desc|
        opts.on(
          param_option(name, desc),
          desc[:label] || name.to_s
        ) { |v| @credentials[name] = v }
      end

      opts.on('--token TOKEN', 'Token') do |t|
        @token = t
      end

      opts.on('--token-lifetime LIFETIME',
              %i[fixed renewable_manual renewable_auto permanent],
              'Token lifetime, defaults to renewable_auto') do |l|
        @lifetime = l
      end

      opts.on('--token-interval SECONDS', Integer,
              'How long will token be valid in seconds') do |s|
        @interval = s
      end

      opts.on('--new-token', 'Request new token') do
        @token = nil
      end

      via = %i[query_param header]

      opts.on('--token-via VIA', via,
              'Send token as a query parameter or in HTTP header',
              "(#{via.join(', ')})") do |v|
        @via = v.to_sym
      end
    end

    def validate
      return if @token

      request_credentials.each do |name, desc|
        if !@credentials.has_key?(name) && desc[:required]
          @credentials[name] = read_param(name, desc)
        end
      end
    end

    def authenticate
      opts = {
        token: @token,
        lifetime: @lifetime || :renewable_auto,
        interval: @interval,
        valid_to: @valid_to,
        via: @via
      }

      opts.update(@credentials) if @credentials

      @communicator.authenticate(:token, opts) do |_action, params|
        ret = {}

        params.each do |name, desc|
          ret[name] = read_param(name, desc)
        end

        ret
      end
    end

    def save
      super.update({ via: @via, interval: @interval })
    end

    protected

    def request_credentials
      desc[:resources][:token][:actions][:request][:input][:parameters].reject do |name, _|
        %i[lifetime interval].include?(name)
      end
    end
  end
end
