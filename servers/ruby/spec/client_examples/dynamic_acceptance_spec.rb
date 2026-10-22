require 'spec_helper'
require 'rack/mock'
require_relative 'dynamic_acceptance'

RSpec.describe DynamicDocumentationAcceptance do
  it 'extracts actual six-language HTML panels from the mounted fixture' do
    request = Rack::MockRequest.new(DynamicDocumentationAPI.build.app)
    response = request.get('http://example.test/mount/v2/', 'HTTP_HOST' => 'example.test')
    expect(response.status).to eq(200), response.body
    panels = described_class.extract(response.body)
    described_class::VARIANTS.each do |variant|
      selected = panels.select { |panel| panel[:variant] == variant }
      expect(selected.map { |panel| panel[:id].split('-').first }).to include('init', 'auth', 'example')
      expect(selected.count { |panel| panel[:id].start_with?('example-') }).to eq(2)
      expect(selected.last[:source]).to include('http://example.test/mount/')
      expect(selected.last[:source]).not_to include('&quot;')
    end
  end

  it 'records real success and failure request values without source rewriting' do
    request = Rack::MockRequest.new(DynamicDocumentationAPI.build.app)
    payload = { widget: { name: '', enabled: false, count: 0, nullable: nil, payload: DynamicDocumentationAPI::PAYLOAD } }
    headers = {
      'CONTENT_TYPE' => 'application/json',
      'HTTP_AUTHORIZATION' => "Basic #{['fixture-user:fixture-password'].pack('m0')}",
      input: JSON.generate(payload)
    }
    path = 'http://example.test/mount/v2/parents/7/children/name%20with%20space'
    response = request.post(path, headers)
    expect(response.status).to eq(200), response.body
    expect(JSON.parse(response.body).fetch('status')).to be(true)
    expect(DynamicDocumentationAPI.receipts.last[:input][:payload]).to eq(DynamicDocumentationAPI::PAYLOAD)
    payload[:widget][:count] = -1
    response = request.post(path, headers.merge(input: JSON.generate(payload)))
    expect(response.status).to eq(400), response.body
    expect(JSON.parse(response.body).fetch('message')).to eq('DOC_FAILURE')
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

  it 'preserves separate existing-token and challenge output before completion assertions' do
    Dir.mktmpdir('haveapi-doc-output-') do |directory|
      command = ['ruby', '-e', 'puts ENV.key?("HAVEAPI_TOKEN") ? "Authenticated" : "Discovery or authentication failed"']
      path = File.join(directory, 'example-12.log')
      challenge_path = File.join(directory, 'example-12-challenge.log')
      result = described_class.run!(*command, chdir: directory, env: { 'HAVEAPI_TOKEN' => 'fixture-token' }, log_path: path)
      challenge = described_class.run!(*command, chdir: directory, env: { 'HAVEAPI_TOKEN' => nil }, log_path: challenge_path)
      expect(File.read(path)).to eq(result)
      expect(File.read(challenge_path)).to eq(challenge)
      expect(result).to include('Authenticated')
      expect(challenge).to include('Discovery or authentication failed')
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
