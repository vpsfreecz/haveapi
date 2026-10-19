require_relative '../spec_helper'

RSpec.describe HaveAPI::RustClient::Snapshot do
  include RustGeneratorFixtures

  it 'normalizes object keys while preserving array order' do
    expect(described_class.canonical({ 'b' => 1, 'a' => [2, 1] })).to eq("{\n  \"a\": [\n    2,\n    1\n  ],\n  \"b\": 1\n}\n")
  end

  it 'strips structural prose without dropping fields named default, description or format' do
    parameter_map = %w[default description format token].to_h do |name|
      [name, parameter.merge('label' => 'Prose', 'description' => 'Private prose')]
    end
    source = { 'resources' => { 'default' => { 'actions' => {
      'show' => { 'input' => io(parameter_map), 'description' => 'Prose', 'examples' => ['secret'] }
    } } } }
    cleaned = described_class.sanitize(source)
    expect(cleaned.dig('resources', 'default', 'actions', 'show').keys).to eq(['input'])
    result = cleaned.dig('resources', 'default', 'actions', 'show', 'input', 'parameters')
    expect(result.keys).to eq(parameter_map.keys)
    expect(result.values.flat_map(&:keys)).not_to include('label', 'description')
  end

  it 'keeps Custom defaults and choice keys while removing choice labels and protected defaults' do
    diagnostics = []
    source = io(
      'custom' => parameter('Custom').merge('default' => { 'description' => 'data', 'resources' => { 'label' => 'data' } }),
      'secret' => parameter.merge('protected' => true, 'default' => 'credential'),
      'choice' => parameter.merge('validators' => { 'include' => { 'values' => { 'description' => 'Prose' }, 'message' => 'Prose' } })
    )
    cleaned = described_class.sanitize(source, diagnostics:)
    expect(cleaned.dig('parameters', 'custom', 'default')).to eq(source.dig('parameters', 'custom', 'default'))
    expect(cleaned.dig('parameters', 'secret')).not_to have_key('default')
    expect(cleaned.dig('parameters', 'choice', 'validators', 'include')).to eq('values' => { 'description' => nil })
    expect(diagnostics).to eq(['removed protected default: parameters/secret'])
  end

  it 'preserves auth discovery and global token action structure' do
    source = { 'authentication' => { 'token' => {
      'http_header' => 'X-Token', 'description' => 'Prose',
      'resources' => { 'token' => { 'actions' => { 'request' => action(path: '/_auth/token') } } }
    } } }
    cleaned = described_class.sanitize(source)
    expect(cleaned.dig('authentication', 'token', 'http_header')).to eq('X-Token')
    expect(cleaned.dig('authentication', 'token', 'resources', 'token', 'actions', 'request', 'path')).to eq('/_auth/token')
  end

  it 'rejects omitted/mismatched API versions and unsupported protocol majors' do
    expect { described_class.version!(nil) }.to raise_error(HaveAPI::RustClient::Error, /explicit/)
    expect { described_class.validate(snapshot.merge('api_version' => '2.0')) }.to raise_error(HaveAPI::RustClient::Error, /mismatch/)
    expect { described_class.validate(snapshot.merge('protocol_version' => '3.0')) }.to raise_error(HaveAPI::RustClient::Error, /protocol/)
  end

  it 'rejects credential, query, fragment and unsafe endpoint paths' do
    %w[https://user:secret@example.test/v1.0/ https://example.test/v1.0/?token=x https://example.test/v1.0/#x
       https://example.test/%2e%2e/v1.0/].each do |url|
      expect { described_class.endpoint!(url) }.to raise_error(HaveAPI::RustClient::Error)
    end
  end
end
