require 'spec_helper'
require_relative '../../test_support/performance_endpoint_fixture'

RSpec.describe HaveAPI::PerformanceFixtures::Endpoints do
  let(:scenarios) { [] }

  def build(id = 'api.basic_get', **dimensions)
    scenario = described_class.build(id:, dimensions:)
    scenarios << scenario
    scenario
  end

  def headers(user = 'member')
    { 'HTTP_HOST' => 'example.test', 'HTTP_ACCEPT' => 'application/json',
      'HTTP_AUTHORIZATION' => "Basic #{["#{user}:#{described_class::PASSWORD}"].pack('m0')}",
      'CONTENT_TYPE' => 'application/json' }
  end

  def json_request(request, method, path, body = nil, user: 'member')
    response = request.request(method, "/performance/v1/#{path}",
                               headers(user).merge(input: body.nil? ? '' : JSON.generate(body)))
    [response, JSON.parse(response.body)]
  end

  after do
    scenarios.each(&:close)
  end

  it 'retains the seven quick cases and adds only the accepted weekly shapes' do
    quick = described_class.cases
    expect(quick.map { |item| item[:id] }).to eq(described_class::CASE_IDS)
    expect(quick.last).to eq(id: 'api.list', dimensions: { rows: 32 })
    expect(quick[0...-1].map { |item| item[:dimensions] }).to all(eq({}))
    weekly = described_class.cases(profile: 'weekly')
    expect(weekly.first(quick.length)).to eq(quick)
    additions = [
      { id: 'api.list', dimensions: { rows: 1024, user: 'member' } },
      { id: 'api.list', dimensions: { rows: 1024, user: 'admin' } },
      { id: 'api.basic_get', dimensions: { user: 'admin' } }
    ]
    expect(weekly.drop(quick.length)).to eq(additions)
    expect(weekly.uniq).to eq(weekly)
  end

  it 'executes and validates every real quick-case response and counter record' do
    described_class.cases.each do |item|
      scenario = build(item[:id], **item[:dimensions])
      scenario.reset!(iterations: 3)
      responses = Array.new(3) { scenario.call }
      responses.each_with_index do |response, index|
        identity = scenario.validate!(response, index:)
        expect(identity).to include(http_status: 200, body_bytes: response.body.bytesize,
                                    body_sha256: Digest::SHA256.hexdigest(response.body))
        expect(identity[:envelope_status]).to eq(item[:id] != 'api.invalid_post')
        expect(identity[:canonical_body]).to eq(JSON.parse(response.body))
        expect(identity[:canonical_sha256]).to eq(HaveAPI::Performance::Identity.digest(JSON.parse(response.body)))
      end
      executions = item[:id] == 'api.invalid_post' ? 0 : 1
      expect(scenario.counters).to eq(operations: Array.new(3) { { queries: 0, authorizations: 1, executions: } })
    end
  end

  it 'validates the weekly large-list and administrator shapes' do
    described_class.cases(profile: 'weekly').drop(described_class::CASE_IDS.length).each do |item|
      scenario = build(item[:id], **item[:dimensions])
      scenario.reset!(iterations: 1)
      identity = scenario.validate!(scenario.call, index: 0)
      output = identity.fetch(:canonical_body).fetch('response').fetch('probe')
      records = item[:id] == 'api.list' ? output : [output]
      expect(records.length).to eq(item[:dimensions].fetch(:rows, 1))
      records.each do |record|
        expect(record.has_key?('secret')).to eq(item[:dimensions][:user] == 'admin')
      end
      expect(scenario.counters).to eq(operations: [{ queries: 0, authorizations: 1, executions: 1 }])
    end
  end

  it 'rejects a corrupted early response even when the final response is valid' do
    scenario = build
    scenario.reset!(iterations: 2)
    first = scenario.call
    last = scenario.call
    body = JSON.parse(first.body)
    body['response']['probe']['count'] = '0'
    broken = Rack::MockResponse.new(200, first.headers, JSON.generate(body))

    expect { scenario.validate!(last, index: 1) }.not_to raise_error
    expect { scenario.validate!(broken, index: 0) }.to raise_error(/Unexpected output/)
    expect { scenario.validate!(Rack::MockResponse.new(403, {}, '{}'), index: 0) }
      .to raise_error(/HTTP status/)
    duplicate = Rack::MockResponse.new(200, first.headers, first.body.sub('"status":true', '"status":false,"status":true'))
    expect { scenario.validate!(duplicate, index: 0) }.to raise_error(HaveAPI::Performance::ContractError, /duplicate/i)
  end

  it 'preserves typed zero, false, empty, null, nested Custom data and omission' do
    scenario = build('api.typed_post')
    scenario.reset!(iterations: 1)
    response = scenario.call
    scenario.validate!(response, index: 0)
    output = JSON.parse(response.body).fetch('response').fetch('probe')

    expect(output).to include('count' => 0, 'ratio' => 1.25, 'enabled' => false, 'label' => '', 'nullable' => nil,
                              'at' => '2020-01-01T00:00:00+00:00', 'payload' => { 'nested' => [0, false, '', nil] })
    expect(output).not_to have_key('omitted')
  end

  it 'uses distinct Basic and token providers with real credential failures' do
    basic = build('api.basic_get')
    token = build('api.token_get')
    [basic, token].each { |scenario| scenario.reset!(iterations: 1) }
    expect(basic.validate!(basic.call, index: 0)).to eq(token.validate!(token.call, index: 0))
    request = Rack::MockRequest.new(basic.app)
    missing = request.get('/performance/v1/probes/secure', 'HTTP_HOST' => 'example.test')
    bad_basic = request.get('/performance/v1/probes/secure', headers.merge('HTTP_AUTHORIZATION' => 'Basic invalid'))
    bad_token = request.get('/performance/v1/probes/secure', headers.merge('HTTP_AUTHORIZATION' => '',
                                                                           'HTTP_X_HAVEAPI_AUTH_TOKEN' => 'invalid'))
    expect([missing.status, bad_basic.status, bad_token.status]).to eq([401, 401, 401])
    [missing, bad_basic, bad_token].each { |response| expect(JSON.parse(response.body)['status']).to be(false) }
    denied, body = json_request(request, 'GET', 'probes/admin')
    expect(denied.status).to eq(403)
    expect(body.fetch('status')).to be(false)
    allowed, body = json_request(request, 'GET', 'probes/admin', user: 'admin')
    expect(allowed.status).to eq(200)
    expect(body.dig('response', 'probe', 'secret')).to eq('ADMIN_ONLY_VALUE')
  end

  it 'executes real CRUD, isolates stores and resets writes outside measured requests' do
    scenario = build('api.list', rows: 1)
    other = build('api.list', rows: 1)
    scenario.reset!(iterations: 1)
    other.reset!(iterations: 1)
    request = Rack::MockRequest.new(scenario.app)
    created, body = json_request(request, 'POST', 'items', { probe: { label: 'created' } })
    expect(created.status).to eq(200)
    expect(body.fetch('status')).to be(true)
    expect(body.dig('response', 'probe')).to include('id' => 2, 'label' => 'created')
    _, body = json_request(request, 'GET', 'items/2')
    expect(body.dig('response', 'probe', 'label')).to eq('created')
    _, body = json_request(request, 'PUT', 'items/2', { probe: { label: 'updated' } })
    expect(body.dig('response', 'probe', 'label')).to eq('updated')
    _, body = json_request(request, 'DELETE', 'items/2')
    expect(body.dig('response', 'probe', 'label')).to eq('updated')
    missing, body = json_request(request, 'GET', 'items/2')
    expect(missing.status).to eq(404)
    expect(body.fetch('status')).to be(false)
    json_request(request, 'POST', 'items', { probe: { label: 'discarded by reset' } })
    expect(other.validate!(other.call, index: 0)[:envelope_status]).to be(true)
    scenario.reset!(iterations: 1)
    expect(scenario.validate!(scenario.call, index: 0)[:envelope_status]).to be(true)
  end

  it 'does not mutate timed counter records through direct app requests' do
    scenario = build
    scenario.reset!(iterations: 1)
    response = scenario.call
    before = Marshal.dump(scenario.counters)
    request = Rack::MockRequest.new(scenario.app)
    json_request(request, 'GET', 'probes/secure')
    json_request(request, 'POST', 'items', { probe: { label: 'untimed' } })

    expect(Marshal.dump(scenario.counters)).to eq(before)
    expect { scenario.validate!(response, index: 0) }.not_to raise_error
  end

  it 'rejects malformed bodies, missing routes and invalid typed input through real middleware' do
    scenario = build
    request = Rack::MockRequest.new(scenario.app)
    ['{', '[]', 'null'].each do |input|
      response = request.post('/performance/v1/probes/typed', headers.merge(input:))
      expect(response.status).to eq(400)
      expect(JSON.parse(response.body)['status']).to be(false)
    end
    response = request.get('/performance/v1/not-a-route', headers)
    expect(response.status).to eq(404)
    expect(JSON.parse(response.body)['status']).to be(false)
    response = request.post('/performance/v1/probes/typed', headers.merge(input: '{"probe":{"count":"wrong"}}'))
    expect(response.status).to eq(200)
    expect(JSON.parse(response.body).fetch('errors')).to have_key('count')
  end

  it 'alternates privileged and restricted users without exposing hidden fields' do
    scenario = build
    request = Rack::MockRequest.new(scenario.app)
    %w[admin member admin].each do |user|
      _, body = json_request(request, 'GET', 'probes/secure', user:)
      output = body.fetch('response').fetch('probe')
      if user == 'admin'
        expect(output.fetch('secret')).to eq('ADMIN_ONLY_VALUE')
      else
        expect(output).not_to have_key('secret')
        expect(JSON.generate(body)).not_to include('ADMIN_ONLY_VALUE')
      end
    end
  end

  it 'requires reset and every operation record, and rejects overflow and damaged counters' do
    scenario = build
    expect { scenario.call }.to raise_error(/reset!/)
    expect { scenario.counters }.to raise_error(/Missing operation/)
    scenario.reset!(iterations: 2)
    first = scenario.call
    expect { scenario.counters }.to raise_error(/Missing operation/)
    scenario.call
    expect { scenario.call }.to raise_error(/More calls/)
    expect { scenario.validate!(first, index: -1) }.to raise_error(ArgumentError)
    expect { scenario.validate!(first, index: 2) }.to raise_error(/not called/)
    scenario.counters[:operations].first[:queries] = 1
    expect { scenario.validate!(first, index: 0) }.to raise_error(/counts/)
    expect { scenario.counters }.to raise_error(/counts/)
    scenario.reset!(iterations: 1)
    scenario.validate!(scenario.call, index: 0)
    scenario.close
    expect { scenario.call }.to raise_error(/closed/)
    expect { scenario.reset!(iterations: 1) }.to raise_error(/closed/)
  end

  it 'fails closed on unknown cases, profiles, dimensions, users and invalid batch sizes' do
    expect { described_class.cases(profile: 'other') }.to raise_error(ArgumentError)
    expect { build('api.unknown') }.to raise_error(ArgumentError)
    expect { build('api.list', rows: 0) }.to raise_error(ArgumentError)
    expect { build('api.list', rows: '32') }.to raise_error(ArgumentError)
    expect { build('api.list', user: 'unknown') }.to raise_error(ArgumentError)
    expect { build('api.list', accidental: true) }.to raise_error(ArgumentError)
    expect { build.reset!(iterations: 0) }.to raise_error(ArgumentError)
  end
end
