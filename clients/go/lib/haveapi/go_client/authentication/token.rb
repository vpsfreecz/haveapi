require 'haveapi/go_client/authentication/base'

module HaveAPI::GoClient
  class Authentication::Token < Authentication::Base
    register :token

    # HTTP header the token is sent in
    # @return [String]
    attr_reader :http_header

    # Query parameter the token is sent in
    # @return [String]
    attr_reader :query_parameter

    # Resource for token manipulation
    # @return [Resource]
    attr_reader :resource

    def initialize(api_version, name, desc)
      @http_header = desc[:http_header]
      @query_parameter = desc[:query_parameter]
      @resource = Resource.new(
        api_version,
        :token,
        desc[:resources][:token],
        prefix: 'auth_token'
      )
      resource.resolve_associations
    end

    def generate(gen)
      ErbTemplate.render_to_if_changed(
        'authentication/token.go',
        {
          package: gen.package,
          auth: self
        },
        File.join(gen.dst, 'auth_token.go')
      )

      resource.generate(gen)
    end

    # @return [Action]
    def request_action
      @request_action ||= resource.actions.detect { |a| a.name == 'request' }
    end

    # @return [Array<Action>]
    def custom_actions
      @custom_actions ||= resource.actions.reject do |a|
        %w[request renew revoke].include?(a.name)
      end
    end
  end
end
