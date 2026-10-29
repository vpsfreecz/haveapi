# Deliberately avoid the component spec_helper: offline CLI checks need no server.
require 'stringio'
require 'tmpdir'
require 'haveapi/schema'
require 'haveapi/go_client/cli'

RSpec.describe HaveAPI::GoClient::Cli do
  let(:err) { StringIO.new }
  let(:generator) { double(generate: true, go_fmt: true) }
  let(:generator_class) { Class.new }
  let(:snapshot) do
    HaveAPI::Schema::Snapshot.from_description(
      api_version: '1.0', protocol_version: '2.0', source_url: 'https://example.test/v1.0/', profile: 'fixture',
      description: {
        'help' => '/v1.0/', 'meta' => { 'namespace' => '_meta' }, 'authentication' => {},
        'resources' => { 'widget' => { 'actions' => { 'show' => {
          'path' => '/v1.0/widgets/{widget_id}', 'method' => 'GET', 'aliases' => [], 'auth' => false,
          'input' => { 'parameters' => {}, 'namespace' => 'widget', 'layout' => 'object' },
          'output' => { 'parameters' => { 'name' => { 'type' => 'String' } }, 'namespace' => 'widget', 'layout' => 'object' },
          'meta' => { 'global' => nil, 'object' => nil }
        } }, 'resources' => {} } }
      }
    )
  end

  before do
    stub_const('HaveAPI::GoClient::Generator', generator_class)
    allow(described_class).to receive(:require).with('haveapi/schema').and_call_original
    allow(described_class).to receive(:require).with('haveapi/go_client').and_return(true)
    allow(generator_class).to receive_messages(new: generator, from_description: generator)
  end

  it 'delegates fetch options and status unchanged' do
    args = ['https://example.test/v1.0/', '--api-version', '1.0', '--profile', 'public', '--output', 'schema.json']
    out = StringIO.new
    allow(HaveAPI::Schema::FetchCommand).to receive(:run).and_return(1)
    expect(described_class.run(['fetch', *args], out:, err:)).to eq(1)
    expect(HaveAPI::Schema::FetchCommand).to have_received(:run).with(args, out:, err:, command_name: 'haveapi-go-client')
  end

  it 'rejects missing and mismatched versions before generation or output mutation' do
    Dir.mktmpdir do |root|
      path = File.join(root, 'schema.json')
      File.write(path, HaveAPI::Schema::Snapshot.canonical(snapshot))
      args = ['generate', '--schema', path, '--output', File.join(root, 'out')]
      expect(described_class.run(args, err:)).to eq(1)
      expect(err.string).to include('explicit numeric API version')
      expect(described_class.run(args + ['--api-version', '2.0'], err:)).to eq(1)
      expect(err.string).to include('differs from snapshot')
      expect(generator_class).not_to have_received(:from_description)
      expect(Dir.children(root)).to eq(['schema.json'])
    end
  end

  it 'passes recursively symbolized saved description to the existing generator then formats' do
    Dir.mktmpdir do |root|
      path = File.join(root, 'schema.json')
      output = File.join(root, 'out')
      File.write(path, HaveAPI::Schema::Snapshot.canonical(snapshot))
      args = ['generate', '--schema', path, '--api-version', '1.0', '--output', output, '--module', 'example.test/widget', '--package', 'widgets']
      expected = JSON.parse(JSON.generate(snapshot.fetch('description')), symbolize_names: true)
      expect(described_class.run(args, err:)).to eq(0)
      expect(generator_class).to have_received(:from_description).with(expected, output, hash_including(version: '1.0', module: 'example.test/widget', package: 'widgets'))
      expect(generator).to have_received(:generate)
      expect(generator).to have_received(:go_fmt)
      expect(args.first).to eq('generate')
    end
  end

  it 'retains positional legacy default-version and raw Basic options' do
    expect(described_class.run(['--basic-user', 'demo', '--basic-password', 'test-only', 'https://example.test/', 'out'], err:)).to eq(0)
    expect(generator_class).to have_received(:new).with('https://example.test/', 'out', { package: 'client', basic_user: 'demo', basic_password: 'test-only' })
    expect(generator).to have_received(:generate)
    expect(generator).to have_received(:go_fmt)
  end

  it 'retains the explicit legacy version and rejects raw password in saved mode' do
    expect(described_class.run(['--version', '1.0', 'https://example.test/', 'out'], err:)).to eq(0)
    expect(generator_class).to have_received(:new).with('https://example.test/', 'out', { package: 'client', version: '1.0' })
    expect(described_class.run(['generate', '--basic-password', 'test-only'], err:)).to eq(1)
    expect(err.string).to include('invalid option')
  end

  context 'when formatting fails' do
    before do
      allow(generator).to receive(:go_fmt).and_raise('go fmt failed')
    end

    it 'propagates the failure from saved-schema generation' do
      Dir.mktmpdir do |root|
        path = File.join(root, 'schema.json')
        File.write(path, HaveAPI::Schema::Snapshot.canonical(snapshot))

        expect do
          described_class.run([
                                'generate', '--schema', path, '--api-version', '1.0',
                                '--output', File.join(root, 'out')
                              ], err:)
        end.to raise_error(RuntimeError, 'go fmt failed')
      end
    end

    it 'propagates the failure from legacy generation' do
      expect do
        described_class.run(['https://example.test/', 'out'], err:)
      end.to raise_error(RuntimeError, 'go fmt failed')
    end
  end
end
