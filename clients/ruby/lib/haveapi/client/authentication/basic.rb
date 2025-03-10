require 'haveapi/client/authentication/base'

module HaveAPI::Client::Authentication
  class Basic < Base
    register :basic

    def resource
      RestClient::Resource.new(
        @communicator.url,
        user: @opts[:user],
        password: @opts[:password],
        verify_ssl: @communicator.verify_ssl
      )
    end

    def user = @opts.[](:user)
    def password = @opts.[](:password)
  end
end
