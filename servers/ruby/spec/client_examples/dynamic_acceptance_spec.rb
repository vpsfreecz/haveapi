require 'spec_helper'
require 'rack/mock'
require_relative 'dynamic_acceptance'

RSpec.describe DynamicDocumentationAcceptance do
  let(:trace) { StringIO.new }
  let(:request) do
    Rack::MockRequest.new(DynamicDocumentationAPI::RequestTrace.new(DynamicDocumentationAPI.build.app, output: trace))
  end

  def receipt_snapshot
    JSON.parse(request.get('/__acceptance_receipts').body)
  end

  def setup_panel(provider = nil, detail: :simple)
    { id: 'fixture-panel', group: provider ? "auth-#{provider}-examples" : 'init-examples', detail: }
  end

  def json_post(path, payload)
    request.post(path, 'CONTENT_TYPE' => 'application/json', input: JSON.generate(payload))
  end

  it 'extracts the complete actual matrix with eight singleton and28 requested thorough panels' do
    pages = described_class::PAGES.values.map do |query|
      response = request.get("http://example.test/mount/v2/#{query}", 'HTTP_HOST' => 'example.test')
      expect(response.status).to eq(200), response.body
      response.body
    end
    panels = pages.flat_map { |body| described_class.extract(body) }
    expect { described_class.validate_coverage!(panels) }.not_to raise_error
    expect(panels.length).to eq(36)
    expect(panels.count { |panel| panel[:detail] == :simple }).to eq(8)
    expect(panels.count { |panel| panel[:detail] == :thorough }).to eq(28)
    simple = pages.flat_map { |body| described_class.extract(body, detail: :simple) }
    expect(simple.length).to eq(36)
    expect(simple).to all(include(detail: :simple, requested_detail: :simple))
    overlap = panels.map { |panel| panel[:id] } & simple.map { |panel| panel[:id] }
    expect(overlap.length).to eq(8)
    described_class::VARIANTS.each do |variant|
      selected = panels.select { |panel| panel[:variant] == variant }
      expect(selected.map { |panel| panel[:group] }.sort).to eq(described_class::GROUPS.sort)
      expect(selected.last[:source]).to include('http://example.test/mount/')
      expect(selected.last[:source]).not_to include('&quot;')
      expect(selected).to all(include(requested_detail: :thorough))
    end
    expect { described_class.validate_coverage!(panels.drop(1)) }.to raise_error(/Incomplete/)
    expect { described_class.validate_coverage!(panels + [panels.first]) }.to raise_error(/Incomplete/)
  end

  it 'fails malformed missing duplicate or undeclared groups and selected code instead of skipping coverage' do
    html = request.get('/mount/v2/', 'HTTP_HOST' => 'example.test').body
    map = html.match(/data-example-details="([^"]+)"/)[1]
    missing = JSON.parse(CGI.unescapeHTML(map)).except('javascript-callback')
    variants = [
      html.sub(/data-example-details="[^"]+"/, ''),
      html.sub(map, CGI.escapeHTML('{broken')),
      html.sub(map, CGI.escapeHTML(JSON.generate(missing))),
      html.sub(map, CGI.escapeHTML('{"javascript-callback":["simple"],"javascript-callback":["simple"]}')),
      html.sub(map, map.sub('simple', 'unknown')),
      html.sub(/(data-client="javascript-callback"[^>]*data-detail=")simple"/, '\\1other"'),
      html.sub(%r{(<details[^>]*data-client="javascript-callback"[^>]*>.*?</details>)}m) { |panel| panel * 2 },
      html.sub(%r{(<details[^>]*data-client="javascript-callback"[^>]*>).*?</details>}m,
               '\\1<p class="client-limitation">unsupported</p></details>')
    ]
    variants.each_with_index do |invalid, index|
      expect { described_class.extract(invalid) }.to raise_error(StandardError), "Malformed fixture #{index} was accepted"
    end
    group = html.match(%r{<div[^>]*data-example data-example-details=.*?</div>}m)[0]
    expect { described_class.extract(html + group) }.to raise_error(/Duplicate example group/)
    expect { described_class.extract(html, detail: :other) }.to raise_error(/Invalid requested/)
  end

  it 'requires authenticated mounted discovery for the correct provider on each independent run' do
    before = receipt_snapshot
    expect(request.options('/mount/v2/').status).to eq(200)
    anonymous = receipt_snapshot
    delta = described_class.receipt_delta(before, anonymous)
    expect { described_class.verify_completion!(setup_panel, '', delta) }.not_to raise_error
    expect { described_class.verify_completion!(setup_panel('basic'), '', delta) }.to raise_error(/did not complete/)
    headers = { 'basic' => { 'HTTP_AUTHORIZATION' => "Basic #{['user:secret'].pack('m0')}" },
                'token' => { 'HTTP_X_HAVEAPI_AUTH_TOKEN' => 'example-token' },
                'oauth2' => { 'HTTP_X_FIXTURE_OAUTH2' => 'example-access-token' } }
    headers.each do |provider, credentials|
      before = receipt_snapshot
      expect(request.options('/mount/v2/', credentials).status).to eq(200)
      delta = described_class.receipt_delta(before, receipt_snapshot)
      expect { described_class.verify_completion!(setup_panel(provider), '', delta) }.not_to raise_error unless provider == 'token'
      expect { described_class.verify_completion!(setup_panel(provider), 'Discovery or authentication failed', delta) }
        .to raise_error(/Failed callback/)
      expect { described_class.verify_completion!(setup_panel(provider, detail: :thorough), '', delta) }
        .to raise_error(provider == 'token' ? /Token challenge/ : /Missing completion output/)
      expect { described_class.verify_completion!(setup_panel(provider), '', described_class.receipt_delta(receipt_snapshot, receipt_snapshot)) }
        .to raise_error(/did not complete/)
    end
    before = receipt_snapshot
    request.options('/mount/v2/', 'HTTP_AUTHORIZATION' => "Basic #{['user:wrong-secret'].pack('m0')}")
    rejected = described_class.receipt_delta(before, receipt_snapshot)
    expect { described_class.verify_completion!(setup_panel('basic'), '', rejected) }.to raise_error(/did not complete/)
    expect(rejected['events']).to include(include('type' => 'authentication', 'provider' => 'basic', 'authenticated' => false))
    expect(trace.string).not_to include('wrong-secret', 'secret', 'example-token', 'example-access-token', 'Authorization')
  end

  it 'requires request then verification then authenticated discovery inside each token-authentication program' do
    before = receipt_snapshot
    response = json_post('/mount/_auth/token/tokens', token: { user: 'user', password: 'secret', lifetime: 'fixed' })
    expect(response.status).to eq(200), response.body
    incomplete = described_class.receipt_delta(before, receipt_snapshot)
    expect { described_class.verify_completion!(setup_panel('token'), '', incomplete) }.to raise_error(/did not complete/)
    response = json_post('/mount/_auth/token/tokens/verify', token: { token: 'fixture-challenge', code: 'code' })
    expect(response.status).to eq(200), response.body
    request.options('/mount/v2/', 'HTTP_X_HAVEAPI_AUTH_TOKEN' => 'example-token')
    delta = described_class.receipt_delta(before, receipt_snapshot)
    expect { described_class.verify_completion!(setup_panel('token'), '', delta) }.not_to raise_error
    expect { described_class.verify_completion!(setup_panel('token'), '', incomplete) }.to raise_error(/did not complete/)
    before = receipt_snapshot
    json_post('/mount/_auth/token/tokens/verify', token: { token: 'fixture-challenge', code: 'rejected-code' })
    request.options('/mount/v2/', 'HTTP_X_HAVEAPI_AUTH_TOKEN' => 'example-token')
    rejected = described_class.receipt_delta(before, receipt_snapshot)
    expect { described_class.verify_completion!(setup_panel('token'), '', rejected) }.to raise_error(/Token challenge did not complete/)
    expect(rejected['events']).to include(include('type' => 'token_verification_rejected'))
    expect(JSON.generate(delta['events'])).not_to include('user', 'secret', 'example-token', 'code')
    expect(trace.string).not_to include('user', 'secret', 'example-token', 'code', 'rejected-code')
  end

  it 'records real success and failure request values without source rewriting' do
    before = receipt_snapshot
    payload = { widget: { name: '', enabled: false, count: 0, nullable: nil, payload: DynamicDocumentationAPI::PAYLOAD } }
    headers = {
      'CONTENT_TYPE' => 'application/json',
      'HTTP_AUTHORIZATION' => "Basic #{['user:secret'].pack('m0')}",
      input: JSON.generate(payload)
    }
    path = 'http://example.test/mount/v2/parents/7/children/name%20with%20space'
    headers.delete('HTTP_AUTHORIZATION')
    headers['HTTP_X_HAVEAPI_AUTH_TOKEN'] = 'example-token'
    request.options('/mount/v2/', 'HTTP_X_HAVEAPI_AUTH_TOKEN' => 'example-token')
    response = request.post(path, headers)
    expect(response.status).to eq(200), response.body
    expect(JSON.parse(response.body).fetch('status')).to be(true)
    expect(DynamicDocumentationAPI.receipts.last[:input][:payload]).to eq(DynamicDocumentationAPI::PAYLOAD)
    delta = described_class.receipt_delta(before, receipt_snapshot)
    panel = { id: 'success-panel', group: described_class::GROUPS[-2], detail: :thorough }
    expect { described_class.verify_completion!(panel, 'DOC_SUCCESS', delta) }.not_to raise_error
    expect { described_class.verify_completion!(panel, '', delta) }.to raise_error(/Wrong result/)
    expect { described_class.verify_completion!(panel, 'DOC_SUCCESS', delta.merge('actions' => delta['actions'] * 2)) }
      .to raise_error(/did not execute once/)
    before = receipt_snapshot
    request.options('/mount/v2/', 'HTTP_X_HAVEAPI_AUTH_TOKEN' => 'example-token')
    payload[:widget][:count] = -1
    response = request.post(path, headers.merge(input: JSON.generate(payload)))
    expect(response.status).to eq(400), response.body
    expect(JSON.parse(response.body).fetch('message')).to eq('DOC_FAILURE')
    delta = described_class.receipt_delta(before, receipt_snapshot)
    panel[:group] = described_class::GROUPS.last
    expect { described_class.verify_completion!(panel, 'DOC_FAILURE', delta) }.not_to raise_error
  end

  it 'rejects malformed or rewound receipt snapshots and rejected token-login completion' do
    before = receipt_snapshot
    json_post('/mount/_auth/token/tokens', token: { user: 'user', password: 'wrong-secret', lifetime: 'fixed' })
    after = receipt_snapshot
    delta = described_class.receipt_delta(before, after)
    expect(delta['events']).to include(include('type' => 'token_request_rejected'))
    expect { described_class.verify_completion!(setup_panel('token'), '', delta) }.to raise_error(/did not complete/)
    expect { described_class.receipt_delta(after, before) }.to raise_error(/changed before/)
    expect { described_class.receipt_delta([], after) }.to raise_error(/Invalid fixture receipt/)
    expect(trace.string).not_to include('wrong-secret', 'secret')
  end

  it 'preserves subprocess output before reporting a nonzero execution failure' do
    Dir.mktmpdir('haveapi-doc-output-') do |directory|
      path = File.join(directory, 'example-12.log')
      expect do
        described_class.run!('ruby', '-e', 'warn "Discovery or authentication failed"; exit 1', chdir: directory, log_path: path)
      end.to raise_error(RuntimeError, /Discovery or authentication failed/)
      expect(File.read(path)).to include('Discovery or authentication failed')
    end
  end

  it 'traces failed mounted routes without headers, query strings or request bodies' do
    output = StringIO.new
    app = DynamicDocumentationAPI::RequestTrace.new(DynamicDocumentationAPI.build.app, output:)
    request = Rack::MockRequest.new(app)
    response = request.post('http://example.test/mount/mount/_auth/token/tokens?credential=query-secret',
                            'HTTP_AUTHORIZATION' => 'Bearer header-secret', 'CONTENT_TYPE' => 'application/json',
                            input: JSON.generate({ password: 'body-secret' }))
    expect(response.status).to eq(404)
    prefix = 'DYNAMIC_DOCUMENTATION_REQUEST '
    trace = JSON.parse(output.string.delete_prefix(prefix))
    expect(trace).to eq('method' => 'POST', 'path' => '/mount/mount/_auth/token/tokens', 'status' => 404)
    expect(output.string).not_to include('secret', 'credential', 'password', 'Bearer')
  end
end
