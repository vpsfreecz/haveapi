require 'digest'
require 'rack/response'
require 'haveapi'

# Real documentation cookies and provider lookup for specs and benchmarks.
class DocumentationOAuthFixture
  CookieHandler = Struct.new(:response)

  attr_reader :origin, :lookups

  def self.configure(server, users:, origin: 'https://example.org', mount_path: '/')
    fixture = new(users, origin)
    fixture.configure(server, mount_path)
    fixture
  end

  def initialize(users, origin)
    @users = users
    @origin = origin
    @lookups = []
    @expires_at = Time.now.to_f + 3600
  end

  def configure(server, mount_path)
    fixture = self
    config = Class.new(HaveAPI::Authentication::OAuth2::Config) do
      define_method(:base_url) { fixture.origin }
      define_method(:find_user_by_access_token) do |request, token|
        fixture.find_user(@version, request, token)
      end
    end
    server.auth_chain << HaveAPI::Authentication::OAuth2.with_config(config)
    server.documentation_oauth(
      client_id: 'documentation-fixture', client_secret: 'documentation-fixture-client-secret',
      session_secret: 'documentation-fixture-session-secret-' * 3,
      redirect_uri: "#{origin}#{mount_path.chomp('/')}/_documentation/oauth/callback"
    )
  end

  def find_user(version, _request, token)
    @lookups << [version, token]
    @users.fetch(version, {})[token]
  end

  def header_for(server, version:, token:)
    @users.fetch(version).fetch(token)
    handler = CookieHandler.new(Rack::Response.new)
    server.documentation_oauth.send(:write_cookie, handler, 'session', {
                                     'token' => token, 'expires' => @expires_at,
                                     'csrf' => Digest::SHA256.hexdigest("documentation-fixture-csrf:#{token}")
                                   })
    Array(handler.response.headers['set-cookie']).fetch(0).split(';', 2).first
  end
end
