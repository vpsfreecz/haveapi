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
end
