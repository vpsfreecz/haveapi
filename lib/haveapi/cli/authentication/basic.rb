module HaveAPI::CLI::Authentication
  class Basic < Base
    register :basic

    def options(opts)
      opts.on('--username USER', 'User name') do |u|
        @user = u
      end

      opts.on('--password PASSWORD', 'Password') do |p|
        @password = p
      end
    end

    def validate
      @user ||= ask('User name: ') { |q| q.default = nil }.to_s

      @password ||= ask('Password: ') do |q|
        q.default = nil
        q.echo = false
      end.to_s
    end

    def authenticate
      @communicator.authenticate(:basic, {user: @user, password: @password})
    end
  end
end
