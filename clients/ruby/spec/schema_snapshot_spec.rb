require_relative 'schema_spec_helper'

RSpec.describe HaveAPI::Schema::Snapshot do
  include SchemaFixtures

  it 'loads offline without the dynamic client, transport or a bundle' do
    script = <<~RUBY
      require 'haveapi/schema'
      abort 'dynamic client loaded' if defined?(RestClient) || defined?(HaveAPI::Client::Client)
      identity = HaveAPI::Schema.source_identity
      abort 'mutable identity' unless identity.frozen? && identity.values.all?(&:frozen?)
      puts identity.fetch('package_name')
      puts identity.fetch('version')
    RUBY
    lib = File.expand_path('../lib', __dir__)
    out, err, status = Open3.capture3({ 'RUBYOPT' => nil, 'RUBYLIB' => nil }, RbConfig.ruby, '--disable-gems', '-I', lib, '-e', script)
    expect(status.success?).to be(true), err
    expect(out.lines.map(&:strip)).to eq(['haveapi-client', HaveAPI::Client::VERSION])
  end

  it 'uses the established canonical bytes and preserves array order and UTF-8 data' do
    expected = <<~JSON
      {
        "a": "č",
        "z": [
          {
            "a": 2,
            "b": 1
          },
          0
        ]
      }
    JSON
    expect(described_class.canonical('z' => [{ 'b' => 1, 'a' => 2 }, 0], 'a' => 'č')).to eq(expected)
    expect(described_class.sha256(snapshot)).to eq(Digest::SHA256.hexdigest(described_class.canonical(snapshot)))
  end

  it 'matches a mounted format 1 snapshot without rewriting saved data' do
    expected = {
      'schema_format' => 1, 'api_version' => '7.0', 'protocol_version' => '2.0',
      'source_url' => SchemaFixtures::URL, 'profile' => 'fixture', 'mount_path' => '/mount/', 'description' => description
    }
    expect(snapshot).to eq(expected)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'schema.json')
      bytes = described_class.canonical(expected)
      File.write(path, bytes)
      expect(described_class.load(path)).to eq(expected)
      expect(File.binread(path)).to eq(bytes)
    end
  end

  it 'preserves Custom/default and choice keys while stripping prose and protected defaults' do
    diagnostics = []
    data = { 'help' => '/data?token=data', 'fetch_url' => 'custom:value', 'description' => 'data' }
    source = { 'parameters' => {
      'description' => { 'type' => 'Custom', 'default' => data, 'description' => 'prose' },
      'secret' => { 'protected' => true, 'default' => 'fixture-secret' },
      'choice' => { 'validators' => { 'include' => { 'values' => { 'help' => 'label' }, 'message' => 'private' } } }
    } }
    cleaned = described_class.sanitize(source, diagnostics: diagnostics)
    expect(cleaned.dig('parameters', 'description')).to eq('type' => 'Custom', 'default' => data)
    expect(cleaned.dig('parameters', 'secret')).not_to have_key('default')
    expect(cleaned.dig('parameters', 'choice', 'validators', 'include')).to eq('values' => { 'help' => nil })
    expect(diagnostics).to eq(['removed protected default: parameters/secret'])
  end

  it 'rejects nested structural endpoints during capture and load without echoing their values' do
    %w[help path choices_path choices_url].each do |key|
      value = key.end_with?('_url') ? 'https://user:fixture-secret@example.test/' : '/mount/v7.0/?token=fixture-secret'
      schema = snapshot
      schema['description']['resources']['widget']['choices'] = { key => value }
      [-> { described_class.validate(schema) },
       lambda {
         described_class.from_envelope(envelope.merge('response' => schema['description']), api_version: '7.0',
                                                                                            source_url: SchemaFixtures::URL, profile: 'fixture', mount_path: '/mount/')
       }].each do |operation|
        expect(&operation).to raise_error(HaveAPI::Schema::Error) do |error|
          expect(error.message).to include("resources/widget/choices/#{key}")
          expect(error.message).not_to include('fixture-secret', value)
        end
      end
    end
  end

  it 'rejects malformed envelopes, unsafe paths, mismatched versions and protocols' do
    [nil, {}, { 'status' => false }, { 'status' => true }].each do |value|
      expect { described_class.from_envelope(value, api_version: '7.0', source_url: SchemaFixtures::URL, profile: 'fixture') }
        .to raise_error(HaveAPI::Schema::Error)
    end
    %w[/../ /%2e%2e/ /%2f/ /bad%/ //evil/].each { |path| expect(described_class.safe_path?(path)).to be(false) }
    expect { described_class.validate(snapshot.merge('protocol_version' => '3.0')) }.to raise_error(HaveAPI::Schema::Error)
    expect { described_class.validate(snapshot.merge('api_version' => '8.0')) }.to raise_error(HaveAPI::Schema::Error)
    expect { described_class.endpoint!('https://user:secret@example.test/v7.0/') }.to raise_error(HaveAPI::Schema::Error)
  end

  it 'binds source identity to the actual version and all five shared logical source files' do
    lib = File.expand_path('../lib', __dir__)
    paths = %w[haveapi/schema.rb haveapi/schema/snapshot.rb haveapi/schema/capture.rb
               haveapi/schema/fetch_command.rb haveapi/client/version.rb].sort
    digest = Digest::SHA256.new
    paths.each { |path| digest.update(path).update("\0").update(File.binread(File.join(lib, path))).update("\0") }
    expect(HaveAPI::Schema.source_identity).to eq(
      'package_name' => 'haveapi-client', 'version' => HaveAPI::Client::VERSION, 'source_sha256' => digest.hexdigest
    )
  end

  it 'keeps relative owned-file segments compatible without relaxing absolute endpoint paths' do
    expect(described_class.safe_segments?('resources/widget/show.rs')).to be(true)
    expect(described_class.safe_segments?('/mount/v7.0/')).to be(true)
    ['../outside.rs', 'resources/./show.rs', 'resources/%2e%2e/show.rs', 'resources/%2f/show.rs',
     'resources/%5c/show.rs', 'resources/bad%/show.rs', 'resources/with space.rs', "resources/\nshow.rs",
     'resources/show.rs?token=data', 'resources/show.rs#fragment', '//outside', nil].each do |path|
      expect(described_class.safe_segments?(path)).to be(false)
    end
    expect(described_class.safe_path?('resources/widget/show.rs')).to be(false)
    expect { described_class.endpoint!('https://schema.example.test/mount/%2e%2e/v7.0/') }
      .to raise_error(HaveAPI::Schema::Error)
    expect { described_class.validate_machine_endpoint('path', 'resources/widget/show.rs') }
      .to raise_error(HaveAPI::Schema::Error)
  end
end
