require 'spec_helper'
require_relative '../../benchmarks/endpoints'
require_relative '../../test_support/documentation_performance_fixture'

describe HaveAPI::Performance::DocumentationScenario, '#call' do
  def scenario(id, user = 'admin')
    HaveAPI::Performance::DocumentationScenario.new(id:, dimensions: { size: 1, user: })
  end

  it 'validates a real cookie token on every HTML page with stable role-specific bodies and counters' do
    page = scenario('docs.html_resources')
    page.reset!(iterations: 3)
    responses = 3.times.map { page.call }
    responses.each_with_index { |response, index| expect(page.validate!(response, index:)[:http_status]).to eq(200) }
    expect(responses.map(&:body).uniq.length).to eq(1)
    expect(responses.first.body).to include('<span class="docs-identity">admin</span>', 'name="csrf"')
    fixture = page.instance_variable_get(:@server).fixture_documentation_oauth
    expect(fixture.lookups).to eq(Array.new(3) { [1, 'documentation-admin'] })
    expect(page.documentation_identity).to eq(mode: 'documentation_oauth_cookie', role: 'admin')
    expect(page.counters[:operations]).to eq(Array.new(3) { { queries: 0, authorizations: 2, executions: 0 } })
  end

  it 'keeps member role filtering and independent CSRF without accepting an admin overview' do
    admin = scenario('docs.html_resources')
    member = scenario('docs.html_resources', 'member')
    [admin, member].each { |page| page.reset!(iterations: 1) }
    administrative = admin.call
    restricted = member.call
    expect(member.validate!(restricted, index: 0)[:http_status]).to eq(200)
    expect(restricted.body).to include('<span class="docs-identity">member</span>')
    expect(restricted.body).not_to include('root-resource0-admin_only')
    expect { member.validate_body!(administrative) }.to raise_error(HaveAPI::Performance::ContractError, /authorization/)
    nonce = ->(response) { response.body.match(/name="csrf" value="([^"]+)"/)[1] }
    expect(nonce.call(restricted)).not_to eq(nonce.call(administrative))
  end

  it 'retains ordinary Basic setup and counter behavior for documentation OPTIONS' do
    page = scenario('docs.options')
    page.reset!(iterations: 1)
    response = page.call
    expect(page.validate!(response, index: 0)[:http_status]).to eq(200)
    expect(page.documentation_identity).to eq(mode: 'basic', role: 'admin')
    expect(page.instance_variable_get(:@headers)).to include('HTTP_AUTHORIZATION')
    expect(page.instance_variable_get(:@headers)).not_to include('HTTP_COOKIE')
    expect(page.instance_variable_get(:@server)).not_to respond_to(:fixture_documentation_oauth)
  end
end
