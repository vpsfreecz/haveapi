require 'spec_helper'
require_relative '../../test_support/documentation_oauth_fixture'

describe DocumentationOAuthFixture do
  api do
    define_resource(:Widget) do
      version 1
      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        output(:hash) { string :value }
        authorize { |user| user&.login == 'admin' ? allow : deny }
      end
    end
  end

  it 'issues real mounted cookies outside requests and validates role, crypto and lookup on every page' do
    user = Struct.new(:login)
    server = HaveAPI::Server.new(self.class::ApiModule)
    server.use_version(1)
    users = { 1 => { 'admin-token' => user.new('admin'), 'member-token' => user.new('member') } }
    fixture = described_class.configure(server, users:, origin: 'https://fixture.example', mount_path: '/api/')
    server.mount('/api/')
    headers = %w[admin-token member-token].to_h { |token| [token, fixture.header_for(server, version: 1, token:)] }
    expect(fixture.lookups).to be_empty
    expect(headers.values.join).not_to include('admin-token', 'member-token')
    allow(server.documentation_oauth).to receive(:read_cookie).and_call_original
    client = Rack::MockRequest.new(server.app)
    url = "#{fixture.origin}/api/v1/?resource=widget"

    first = client.get(url, 'HTTP_HOST' => 'fixture.example', 'HTTP_COOKIE' => headers.fetch('admin-token'))
    second = client.get(url, 'HTTP_HOST' => 'fixture.example', 'HTTP_COOKIE' => headers.fetch('admin-token'))
    expect(first.status).to eq(200)
    expect(second.body).to eq(first.body)
    expect(first.body).to include('admin', 'name="csrf"')
    member = client.get(url, 'HTTP_HOST' => 'fixture.example', 'HTTP_COOKIE' => headers.fetch('member-token'))
    expect(member.status).to eq(404)
    expect(fixture.lookups).to eq([[1, 'admin-token'], [1, 'admin-token'], [1, 'member-token']])
    expect(server.documentation_oauth).to have_received(:read_cookie).exactly(3).times
  end
end
