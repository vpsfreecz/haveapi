require 'haveapi/go_client/authentication/base'

module HaveAPI::GoClient
  class Authentication::Token < Authentication::Base
    register :token

    attr_reader :http_header, :query_parameter, :resource

    def initialize(api_version, name, desc)
      @http_header = desc[:http_header]
      @query_parameter = desc[:query_parameter]
      @resource = Resource.new(
        api_version,
        :token,
        desc[:resources][:token],
        prefix: 'auth_token',
      )
      resource.resolve_associations
    end

    def generate(gen)
      ErbTemplate.render_to_if_changed(
        'authentication/token.go',
        {
          package: gen.package,
          auth: self,
        },
        File.join(gen.dst, 'auth_token.go')
      )

      resource.generate(gen)
    end
  end
end
