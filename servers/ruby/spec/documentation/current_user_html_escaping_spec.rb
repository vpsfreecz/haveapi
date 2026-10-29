# frozen_string_literal: true

require 'spec_helper'

module CurrentUserHtmlEscapingSpec
  User = Struct.new(:id, :login)

  class BasicProvider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, username, password)
      return nil unless password == 'pass'

      User.new(1, username)
    end
  end
end

describe CurrentUserHtmlEscapingSpec do
  api do
    define_resource(:Ping) do
      version 1
      auth false

      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        authorize { allow }
      end
    end
  end

  default_version 1
  auth_chain CurrentUserHtmlEscapingSpec::BasicProvider

  it 'escapes the authenticated login in HTML documentation' do
    payload = '<script>window.__haveapi_xss = 1</script>'

    require_relative '../../test_support/documentation_oauth_fixture'
    server = HaveAPI::Server.new(get_opt(:api_module))
    server.use_version(1)
    fixture = DocumentationOAuthFixture.configure(server, users: { 1 => { 'escaped-user' => CurrentUserHtmlEscapingSpec::User.new(1, payload) } })
    server.mount('/')
    @api = server
    get "#{fixture.origin}/v1/", {}, 'HTTP_COOKIE' => fixture.header_for(server, version: 1, token: 'escaped-user')

    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('text/html')
    expect(last_response.body).not_to include(payload)
    expect(last_response.body).to include(
      '&lt;script&gt;window.__haveapi_xss = 1&lt;/script&gt;'
    )
  end
end
