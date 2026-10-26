require_relative 'schema_spec_helper'

RSpec.describe HaveAPI::Schema::FetchCommand do
  include SchemaFixtures

  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  before do
    allow(HaveAPI::Schema::Capture).to receive(:fetch).and_return(snapshot)
  end

  def run(output, *extra)
    described_class.run([SchemaFixtures::URL, '--api-version', '7.0', '--profile', 'fixture',
                         '--output', output, *extra], out: out, err: err, command_name: 'haveapi-example-client')
  end

  it 'writes canonical bytes atomically and leaves no temporary files' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'schema.json')
      File.write(path, 'old')
      expect(run(path)).to eq(0)
      expect(File.binread(path)).to eq(HaveAPI::Schema::Snapshot.canonical(snapshot))
      expect(Dir.children(dir)).to eq(['schema.json'])
      expect(HaveAPI::Schema::Capture).to have_received(:fetch).with(
        url: SchemaFixtures::URL, api_version: '7.0', profile: 'fixture',
        basic_user: nil, basic_password: nil, token: nil, diagnostics: []
      )
    end
  end

  it 'resolves Basic and existing-token credentials only through named environment variables' do
    stub_const('ENV', ENV.to_h.merge('SCHEMA_TEST_PASSWORD' => 'fixture-password', 'SCHEMA_TEST_TOKEN' => 'fixture-token'))
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'schema.json')
      expect(run(path, '--basic-user', 'user', '--basic-password-env', 'SCHEMA_TEST_PASSWORD')).to eq(0)
      expect(HaveAPI::Schema::Capture).to have_received(:fetch).with(hash_including(basic_user: 'user', basic_password: 'fixture-password'))
      expect(run(path, '--token-env', 'SCHEMA_TEST_TOKEN')).to eq(0)
      expect(HaveAPI::Schema::Capture).to have_received(:fetch).with(hash_including(token: 'fixture-token'))
      expect(out.string + err.string + File.read(path)).not_to include('fixture-password', 'fixture-token')
    end
  end

  it 'rejects invalid credential options before network or output mutation without echoing raw arguments' do
    stub_const('ENV', ENV.to_h.merge('SCHEMA_EMPTY' => '', 'SCHEMA_BAD' => "fixture-secret\n"))
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'schema.json')
      File.write(path, 'old')
      [
        ['--basic-user', 'user'], ['--basic-password-env', 'MISSING'], ['--token-env', 'MISSING'],
        ['--token-env', 'SCHEMA_EMPTY'], ['--token-env', 'SCHEMA_BAD'], ['--token-env', 'bad=name'],
        ['--token-env', 'SCHEMA_EMPTY', '--basic-user', 'user', '--basic-password-env', 'SCHEMA_BAD'],
        ['--basic-password', 'fixture-secret'], ['--unknown=fixture-secret']
      ].each do |args|
        expect(run(path, *args)).to eq(1)
        expect(File.read(path)).to eq('old')
        expect(Dir.children(dir)).to eq(['schema.json'])
      end
      expect(HaveAPI::Schema::Capture).not_to have_received(:fetch)
      expect(err.string).not_to include('fixture-secret')
    end
  end

  it 'preserves old output on capture, validation and atomic-save failures' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'schema.json')
      File.write(path, 'old')
      allow(HaveAPI::Schema::Capture).to receive(:fetch).and_raise(HaveAPI::Schema::Error, 'capture failed')
      expect(run(path)).to eq(1)
      expect(File.read(path)).to eq('old')
      allow(HaveAPI::Schema::Capture).to receive(:fetch).and_return(snapshot.merge('protocol_version' => '3.0'))
      expect(run(path)).to eq(1)
      expect(File.read(path)).to eq('old')
      allow(HaveAPI::Schema::Capture).to receive(:fetch).and_return(snapshot)
      allow(File).to receive(:rename).and_raise(Errno::EACCES, 'fixture-secret')
      expect(run(path)).to eq(1)
      expect(File.read(path)).to eq('old')
      expect(Dir.children(dir)).to eq(['schema.json'])
      expect(err.string).not_to include('fixture-secret')
    end
  end

  it 'refuses a symlink destination or missing parent before acquisition' do
    Dir.mktmpdir do |dir|
      target = File.join(dir, 'target')
      File.write(target, 'keep')
      path = File.join(dir, 'schema.json')
      File.symlink(target, path)
      expect(run(path)).to eq(1)
      expect(File.read(target)).to eq('keep')
      expect(run(File.join(dir, 'missing/schema.json'))).to eq(1)
      expect(Dir.children(dir).sort).to eq(%w[schema.json target])
      expect(HaveAPI::Schema::Capture).not_to have_received(:fetch)
    end
  end

  it 'returns help without loading capture dependencies or creating output' do
    expect(described_class.run(['--help'], out: out, err: err, command_name: 'haveapi-example-client')).to eq(0)
    expect(out.string).to include('fetch URL', '--api-version', '--basic-password-env', '--token-env')
    expect(HaveAPI::Schema::Capture).not_to have_received(:fetch)
  end
end
