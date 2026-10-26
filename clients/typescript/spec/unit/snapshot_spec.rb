require_relative '../spec_helper'

RSpec.describe HaveAPI::TypeScriptClient::Snapshot do
  include TypeScriptFixtures

  it 'canonicalizes nested object keys but preserves meaningful array order' do
    expect(described_class.canonical({ 'z' => [{ 'b' => 1, 'a' => 2 }, 0], 'a' => 'č' }))
      .to eq("{\n  \"a\": \"č\",\n  \"z\": [\n    {\n      \"a\": 2,\n      \"b\": 1\n    },\n    0\n  ]\n}\n")
  end

  it 'delegates canonical bytes and native errors to the common schema implementation' do
    expect(described_class.canonical(snapshot)).to eq(HaveAPI::Schema::Snapshot.canonical(snapshot))
    expect(described_class.sha256(snapshot)).to eq(HaveAPI::Schema::Snapshot.sha256(snapshot))
    expect { described_class.version!(nil) }.to raise_error(HaveAPI::TypeScriptClient::Error)
  end

  it 'removes structural prose and protected defaults without deleting data keys' do
    diagnostics = []
    raw = {
      'description' => 'prose', 'parameters' => {
        'description' => { 'type' => 'Custom', 'label' => 'prose', 'default' => { 'token' => 'data', 'description' => 'data' } },
        'password' => { 'type' => 'String', 'protected' => true, 'default' => 'secret' },
        'choice' => { 'type' => 'String', 'validators' => { 'include' => { 'values' => { 'description' => 'label' }, 'message' => 'prose' } } }
      }
    }
    cleaned = described_class.sanitize(raw, diagnostics:)
    expect(cleaned).not_to have_key('description')
    expect(cleaned.dig('parameters', 'description', 'default')).to eq('token' => 'data', 'description' => 'data')
    expect(cleaned.dig('parameters', 'password')).not_to have_key('default')
    expect(cleaned.dig('parameters', 'choice', 'validators', 'include', 'values')).to eq('description' => nil)
    expect(diagnostics).to eq(['removed protected default: parameters/password'])
  end

  it 'rejects mismatched versions, protocol majors and credential-bearing endpoints' do
    [
      ['api_version', '2.0'], ['protocol_version', '3.0'],
      ['source_url', 'https://user:secret@schema.invalid/api/v1.0/'],
      ['source_url', 'https://schema.invalid/api/v1.0/?token=secret']
    ].each do |key, value|
      expect { described_class.validate(snapshot.merge(key => value)) }.to raise_error(HaveAPI::TypeScriptClient::Error)
    end
  end

  it 'rejects encoded path escapes and malformed snapshot envelopes' do
    %w[/../ /%2e%2e/ /%2f/ //evil/ /bad%/].each { |path| expect(described_class.safe_path?(path)).to be(false) }
    expect { described_class.validate(snapshot.merge('unexpected' => true)) }.to raise_error(HaveAPI::TypeScriptClient::Error, /envelope/)
    expect { described_class.version!(nil) }.to raise_error(HaveAPI::TypeScriptClient::Error, /explicit/)
  end

  it 'rejects nested structural endpoints during capture and saved-schema loading without echoing values' do
    unsafe = {
      'help' => '/api/v1.0/widgets?token=fixture-secret',
      'path' => '/api/v1.0/%2e%2e/widgets',
      'choices_url' => 'https://user:fixture-secret@schema.invalid/api/v1.0/widgets',
      'choices_path' => '/api/v1.0/widgets?token=fixture-secret'
    }
    unsafe.each do |key, value|
      schema = snapshot
      fixture_action(schema)['input']['parameters']['name']['choices'] = { key => value }
      expected = %r{unsafe machine endpoint at resources/widget/actions/update/input/parameters/name/choices/#{key}}
      capture = schema.except('schema_format').transform_keys(&:to_sym)
      expect { described_class.from_description(**capture) }.to raise_error(HaveAPI::TypeScriptClient::Error, expected)
      Dir.mktmpdir do |root|
        path = File.join(root, 'schema.json')
        File.write(path, described_class.canonical(schema))
        expect { described_class.load(path) }.to raise_error(HaveAPI::TypeScriptClient::Error) do |error|
          expect(error.message).to match(expected)
          expect(error.message).not_to include('fixture-secret', value)
        end
      end
    end
  end

  it 'preserves safe structural endpoints and arbitrary Custom, default and choice data keys' do
    schema = snapshot
    fields = fixture_action(schema)['input']['parameters']
    fields['resource'] = parameter('Resource').merge(
      'resource' => ['widget'], 'value_id' => 'id', 'value_label' => 'name',
      'choices' => { 'help' => '/api/v1.0/widgets?method=GET', 'path' => '/api/v1.0/widgets',
                     'choices_url' => 'https://schema.invalid/api/v1.0/widgets' }
    )
    data = { 'help' => '/data?token=ordinary-data', 'path' => '../data', 'fetch_url' => 'custom:value',
             'default' => { 'description' => 'data' } }
    fields['payload'] = parameter('Custom').merge('default' => data)
    fields['choices'] = parameter.merge('validators' => { 'include' => { 'values' => { 'help' => 'label', 'path' => 'label' } } })
    capture = schema.except('schema_format').transform_keys(&:to_sym)
    captured = described_class.from_description(**capture)
    expect(described_class.validate(captured)).to eq(captured)
    captured_fields = fixture_action(captured)['input']['parameters']
    expect(captured_fields['payload']['default']).to eq(data)
    expect(captured_fields['choices']['validators']['include']['values']).to eq('help' => nil, 'path' => nil)
    expect(captured_fields['resource']['choices']).to eq(fields['resource']['choices'])
  end
end
