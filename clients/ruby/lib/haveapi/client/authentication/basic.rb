require 'haveapi/client/authentication/base'

module HaveAPI::Client::Authentication
  class Basic < Base
    register :basic

    def resource
      RestClient::Resource.new(@communicator.url, @opts[:user], @opts[:password])
    end

    def user = @opts.[](:user)
    def password = @opts.[](:password)
  end
end
