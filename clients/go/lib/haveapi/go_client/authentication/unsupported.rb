require 'haveapi/go_client/authentication/base'

module HaveAPI::GoClient
  class Authentication::Unsupported < Authentication::Base
    def initialize(api_version, name, desc)
      super
      warn "Ignoring unsupported authentication method #{name}"
    end

    def generate(gen); end
  end
end
