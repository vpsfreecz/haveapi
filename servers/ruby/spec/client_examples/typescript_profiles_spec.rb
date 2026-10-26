require 'spec_helper'
require 'tmpdir'

describe HaveAPI::ClientExample::Profiles do
  let(:profiles) { described_class.new }
  let(:server) { instance_double(HaveAPI::Server, versions: ['1.0'], root: '/mounted/', describe_version: description) }
  let(:adapter) do
    Class.new do
      def resolve(**); end
      def render(**); end
    end.new
  end
  let(:documentation) { Class.new }
  let(:directory) { Dir.mktmpdir('haveapi-typescript-profile-') }

  def snapshot_path
    File.join(directory, 'snapshot.json')
  end

  def description
    { resources: { widget: { actions: { show: { input: { parameters: { hidden: { default: 'PRIVATE_DEFAULT' } } }, examples: ['PRIVATE_SAMPLE'] } } } },
      authentication: {}, meta: { namespace: '_meta' } }
  end

  before do
    generator = Module.new
    generator.const_set(:VERSION, HaveAPI::VERSION)
    generator.const_set(:Documentation, documentation)
    stub_const('HaveAPI::TypeScriptClient', generator)
    allow(profiles).to receive(:require).with('haveapi/typescript_client/documentation').and_return(true)
    allow(documentation).to receive_messages(from_description: adapter, from_snapshot: adapter)
  end

  after { FileUtils.remove_entry(directory) }

  def mount
    profiles.mount(['1.0'])
    profiles.finalize(server)
  end

  it 'defers one frozen private structural description and preserves omitted package version' do
    config = { package_name: '@example/widget-client' }
    profiles.register('1.0', typescript: config)
    config[:package_name].replace('changed-client')
    expect(documentation).not_to have_received(:from_description)
    mount
    expect(documentation).to have_received(:from_description).once do |**arguments|
      expect(arguments).to include(api_version: '1.0', protocol_version: HaveAPI::PROTOCOL_VERSION, mount_path: '/mounted/',
                                   package_name: '@example/widget-client', package_version: nil)
      expect(arguments[:description]).to be_frozen
      expect(JSON.generate(arguments[:description])).not_to include('PRIVATE_DEFAULT', 'PRIVATE_SAMPLE')
      expect(arguments[:description].dig('resources', 'widget', 'actions', 'show', 'input', 'parameters')).to have_key('hidden')
    end
    profile = profiles.for_version('1.0').fetch(:typescript)
    expect(profile).to have_attributes(language: :typescript, package_name: '@example/widget-client', package_version: nil)
    expect(profile).to be_frozen
    expect(profile.adapter).to be_frozen
    expect(server).to have_received(:describe_version).once
  end

  it 'loads a saved SDK once at registration with explicit package and generator versions' do
    File.write(snapshot_path, JSON.generate(api_version: '1.0'))
    profiles.register('1.0', typescript: { package_name: 'widget-client', package_version: '1.2.3-beta.1+build.4',
                                           snapshot_path:, generator_version: HaveAPI::VERSION })
    File.unlink(snapshot_path)
    mount
    expect(documentation).to have_received(:from_snapshot).once.with(snapshot: { 'api_version' => '1.0' },
                                                                     package_name: 'widget-client', package_version: '1.2.3-beta.1+build.4')
    expect(server).not_to have_received(:describe_version)
  end

  it 'rejects unsafe names, nonconcrete versions and unexpected fields before loading the generator' do
    ['../client', '@scope', 'https://example.test/client', 'UPPERCASE', 'client name', 'node_modules'].each do |name|
      expect { profiles.register('1.0', typescript: { package_name: name }) }.to raise_error(described_class::Invalid, /package/)
    end
    ['latest', '^1.2.3', '1.2', '01.2.3', '1.2.3-01', false].each do |version|
      expect { profiles.register('1.0', typescript: { package_name: 'client', package_version: version }) }.to raise_error(described_class::Invalid, /package/)
    end
    expect { profiles.register('1.0', typescript: { package_name: 'client', factory: 'custom' }) }.to raise_error(described_class::Invalid, /fields/)
    expect(profiles).not_to have_received(:require)
  end

  it 'rejects missing generators, version mismatch, missing snapshots and incompatible factories' do
    allow(profiles).to receive(:require).and_raise(LoadError)
    expect { profiles.register('1.0', typescript: { package_name: 'client' }) }.to raise_error(described_class::Invalid, /not installed/)
    allow(profiles).to receive(:require).and_return(true)
    expect { profiles.register('1.0', typescript: { package_name: 'client', generator_version: '0.0.0' }) }.to raise_error(described_class::Invalid, /version mismatch/)
    expect { profiles.register('1.0', typescript: { package_name: 'client', snapshot_path: '/missing/schema.json' }) }.to raise_error(described_class::Invalid, /absolute local/)
    allow(documentation).to receive(:respond_to?).and_call_original
    allow(documentation).to receive(:respond_to?).with(:from_snapshot).and_return(false)
    expect { profiles.register('1.0', typescript: { package_name: 'client' }) }.to raise_error(described_class::Invalid, /incompatible profile/)
  end

  it 'rejects a different saved API version without publishing any profile' do
    File.write(snapshot_path, JSON.generate(api_version: '2.0'))
    profiles.register('1.0', typescript: { package_name: 'client', snapshot_path: })
    expect { profiles.mount(['1.0']) }.to raise_error(described_class::Invalid, /TypeScript snapshot API version mismatch/)
    expect(profiles.for_version('1.0')).to be_empty
  end

  it 'fails atomically and hides private diagnostics for invalid schemas or adapters' do
    allow(documentation).to receive(:from_description).and_raise('PRIVATE_SCHEMA_DIAGNOSTIC')
    profiles.register('1.0', typescript: { package_name: 'client' })
    expect { mount }.to raise_error(described_class::Invalid, 'Configured documentation client schema or configuration is invalid')
    expect(profiles.for_version('1.0')).to be_empty
  end

  it 'rejects an adapter missing render or resolve during initialization' do
    allow(documentation).to receive(:from_description).and_return(Object.new)
    profiles.register('1.0', typescript: { package_name: 'client' })
    expect { mount }.to raise_error(described_class::Invalid, /adapter interface/)
  end
end
