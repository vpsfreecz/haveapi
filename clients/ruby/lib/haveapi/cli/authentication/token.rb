require 'haveapi/cli/authentication/base'

module HaveAPI::CLI::Authentication
  class Token < Base
    register :token

    def options(opts)
      opts.on('--username USER', 'User name') do |u|
        @user = u
      end

      opts.on('--password PASSWORD', 'Password') do |p|
        @password = p
      end

      opts.on('--token TOKEN', 'Token') do |t|
        @token = t
      end

      opts.on('--token-lifetime LIFETIME',
              %i(fixed renewable_manual renewable_auto permanent),
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

      via = %i(query_param header)

      opts.on('--token-via VIA', via,
              'Send token as a query parameter or in HTTP header',
              "(#{via.join(', ')})") do |v|
        @via = v.to_sym
      end
    end

    def validate
      return if @token

      @user ||= ask('User name: ') { |q| q.default = nil }

      @password ||= ask('Password: ') do |q|
        q.default = nil
        q.echo = false
      end
    end

    def authenticate
      @communicator.authenticate(:token, {
          user: @user,
          password: @password,
          token: @token,
          lifetime: @lifetime || :renewable_auto,
          interval: @interval,
          valid_to: @valid_to,
          via: @via
      })
    end

    def save
      super.update({
                       via: @via,
                       interval: @interval
                   })
    end
  end
end
