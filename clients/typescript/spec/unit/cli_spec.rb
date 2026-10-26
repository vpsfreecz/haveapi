require_relative '../spec_helper'

RSpec.describe HaveAPI::TypeScriptClient::Cli do
  include TypeScriptFixtures

  it 'requires the saved schema, exact version and exclusively owned output' do
    err = StringIO.new
    expect(described_class.run(['fetch'], err:)).to eq(1)
    expect(err.string).to include('fetch requires')
    Dir.mktmpdir do |root|
      schema = File.join(root, 'schema.json')
      File.write(schema, HaveAPI::TypeScriptClient::Snapshot.canonical(snapshot))
      argv = ['generate', '--schema', schema, '--output', File.join(root, 'src/generated')]
      expect(described_class.run(argv, err:)).to eq(1)
      expect(err.string).to include('explicit numeric API version')
      expect(described_class.run(argv + ['--api-version', '2.0'], err:)).to eq(1)
      expect(err.string).to include('differs from snapshot')
      expect(Dir.children(root)).to eq(['schema.json'])
    end
  end

  it 'delegates capture options to the common command without interpreting them' do
    args = ['https://example.test/api/v1.0/', '--api-version', '1.0', '--profile', 'public', '--output', 'schema.json']
    out = StringIO.new
    err = StringIO.new
    allow(HaveAPI::Schema::FetchCommand).to receive(:run).and_return(1)
    expect(described_class.run(['fetch', *args], out:, err:)).to eq(1)
    expect(HaveAPI::Schema::FetchCommand).to have_received(:run).with(args, out:, err:, command_name: 'haveapi-typescript-client')
  end

  it 'reports malformed JSON without a stack trace or source writes' do
    Dir.mktmpdir do |root|
      schema = File.join(root, 'schema.json')
      File.write(schema, '{bad')
      err = StringIO.new
      expect(described_class.run(['generate', '--schema', schema, '--api-version', '1.0', '--output', File.join(root, 'src/generated')], err:)).to eq(1)
      expect(err.string).to include('not valid UTF-8 JSON')
      expect(Dir.children(root)).to eq(['schema.json'])
    end
  end
end
