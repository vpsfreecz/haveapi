module API::Authentication
  class Basic < HaveAPI::Authentication::Basic::Provider
    protected
    def find_user(request, username, password)
      ::User.authenticate(request, username, password)
    end
  end
end
