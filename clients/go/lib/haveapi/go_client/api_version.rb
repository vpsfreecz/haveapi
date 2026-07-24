require 'haveapi/go_client/utils'

module HaveAPI::GoClient
  class ApiVersion
    CLIENT_MEMBERS = %w[
      AllowOAuth2Origin
      Authentication
      DoBodyRequest
      DoQueryStringRequest
      GetLanguage
      GetLanguageHeader
      SetHTTPClient
      SetLanguage
      SetLanguageHeader
      SetTimeout
      Url
    ].freeze

    AUTHENTICATION_CLIENT_MEMBERS = {
      basic: %w[
        SetBasicAuthentication
      ],
      oauth2: %w[
        RevokeAccessToken
        SetExistingOAuth2Auth
      ],
      token: %w[
        RevokeAuthToken
        SetExistingTokenAuth
        SetNewTokenAuth
        SetTokenAuthMode
      ]
    }.freeze

    # @return [Array<Authentication::Base>]
    attr_reader :auth_methods

    # @return [String]
    attr_reader :metadata_namespace

    # @return [Array<Resource>]
    attr_reader :resources

    def initialize(desc)
      @resources = desc[:resources].map do |k, v|
        Resource.new(self, k, v)
      end.sort!

      client_members = CLIENT_MEMBERS + desc[:authentication].keys.flat_map do |name|
        AUTHENTICATION_CLIENT_MEMBERS.fetch(name.to_sym, [])
      end
      Resource.allocate_member_names(@resources, [], reserved: client_members)
      @resources.each(&:resolve_associations)

      @auth_methods = desc[:authentication].map do |k, v|
        AuthenticationMethods.new(self, k, v)
      end

      @metadata_namespace = desc[:meta][:namespace]
    end
  end
end
