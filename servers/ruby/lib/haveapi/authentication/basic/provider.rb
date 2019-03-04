require 'haveapi/authentication/base'

module HaveAPI::Authentication
  module Basic
    # HTTP basic authentication provider.
    #
    # Example usage:
    #   class MyBasicAuth < HaveAPI::Authentication::Basic::Provider
    #     protected
    #     def find_user(request, username, password)
    #       ::User.find_by(login: username, password: password)
    #     end
    #   end
    #
    # Finally put the provider in the authentication chain:
    #   api = HaveAPI.new(...)
    #   ...
    #   api.auth_chain << MyBasicAuth
    class Provider < Base
      def authenticate(request)
        user = nil

        auth = Rack::Auth::Basic::Request.new(request.env)
        if auth.provided? && auth.basic? && auth.credentials
          user = find_user(request, *auth.credentials)
        end

        user
      end

      def describe
        {
            description: "Authentication using HTTP basic. Username and password is passed "+
                         "via HTTP header. Its use is forbidden from web browsers."
        }
      end

      protected
      # Reimplement this method. It has to return an authenticated
      # user or nil.
      def find_user(request, username, password)

      end
    end
  end
end
