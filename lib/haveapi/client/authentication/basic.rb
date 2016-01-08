module HaveAPI::Client::Authentication
  class Basic < Base
    register :basic

    def resource
      RestClient::Resource.new(@communicator.url, @opts[:user], @opts[:password])
    end
  end
end