require 'haveapi/go_client/authentication/base'

module HaveAPI::GoClient
  class Authentication::OAuth2 < Authentication::Base
    register :oauth2

    # HTTP header the token is sent in
    # @return [String]
    attr_reader :http_header

    # Token revocation URL
    # @return [String]
    attr_reader :revoke_url

    def initialize(api_version, name, desc)
      @http_header = desc[:http_header]
      @revoke_url = desc[:revoke_url]
    end

    def generate(gen)
      ErbTemplate.render_to_if_changed(
        'authentication/oauth2.go',
        {
          package: gen.package,
          auth: self
        },
        File.join(gen.dst, 'auth_oauth2.go')
      )
    end
  end
end
