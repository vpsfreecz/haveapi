require 'spec_helper'
require 'tmpdir'

describe HaveAPI::ClientExample::Profiles do
  let(:profiles) { described_class.new }
  let(:directory) { Dir.mktmpdir('haveapi-doc-profiles-') }
  let(:description_path) { File.join(directory, 'description.json') }
  let(:go_config) do
    { import_path: 'example.test/widget/client', module_version: 'v1.2.3', description_path:, generator_version: '0.30.0' }
  end
  let(:adapter) { Object.new }

  before do
    File.write(description_path, JSON.generate({ resources: {} }))
  end

  after { FileUtils.remove_entry(directory) }

  def install_go_adapter
    generator = Module.new
    generator.const_set(:VERSION, '0.30.0')
    documentation = Class.new
    generator.const_set(:Documentation, documentation)
    stub_const('HaveAPI::GoClient', generator)
    allow(profiles).to receive(:require).with('haveapi/go_client/documentation').and_return(true)
    allow(documentation).to receive(:new).and_return(adapter)
    documentation
  end

  it 'needs no optional generator when profiles are absent' do
    allow(profiles).to receive(:require).and_raise('Unexpected optional dependency')
    profiles.mount([1])
    expect(profiles).not_to have_received(:require)
    expect(profiles.for_version(1)).to eq({})
    expect(profiles.for_version(1)).to be_frozen
  end

  it 'loads a matching configured adapter once and keeps schema paths out of the public profile' do
    documentation = install_go_adapter
    profiles.register(1, go: go_config)
    profiles.mount([1])
    File.unlink(description_path)
    profile = profiles.for_version(1).fetch(:go)
    expect(profile).to have_attributes(language: :go, package_name: 'example.test/widget/client', package_version: 'v1.2.3')
    expect(profile).to be_frozen
    expect(profile.adapter).to equal(adapter)
    expect(documentation).to have_received(:new).once.with(description: { 'resources' => {} }, import_path: 'example.test/widget/client', module_version: 'v1.2.3')
    expect(profile).not_to respond_to(:description_path)
  end

  it 'rejects unknown languages, malformed fields and unsafe package configuration' do
    expect { profiles.register(1, python: {}) }.to raise_error(described_class::Invalid, /Unknown/)
    expect { profiles.register(1, go: go_config.merge(unexpected: 'value')) }.to raise_error(described_class::Invalid, /fields/)
    expect { profiles.register(1, go: go_config.merge(import_path: "example.test/\nsource")) }.to raise_error(described_class::Invalid, /package/)
    expect { profiles.register(1, go: go_config.merge(module_version: 'latest')) }.to raise_error(described_class::Invalid, /package/)
  end

  it 'rejects missing adapters, mismatched generator versions and missing files at registration' do
    allow(profiles).to receive(:require).and_raise(LoadError)
    expect { profiles.register(1, go: go_config) }.to raise_error(described_class::Invalid, /not installed/)
    install_go_adapter
    expect { profiles.register(1, go: go_config.merge(generator_version: '0.29.0')) }.to raise_error(described_class::Invalid, /version mismatch/)
    expect { profiles.register(1, go: go_config.merge(description_path: 'relative.json')) }.to raise_error(described_class::Invalid, /absolute local/)
  end

  it 'rejects duplicate profiles, unselected versions and registration after mount' do
    install_go_adapter
    profiles.register(1, go: go_config)
    expect { profiles.register('1', go: go_config) }.to raise_error(described_class::Invalid, /Duplicate/)
    expect { profiles.mount([2]) }.to raise_error(described_class::Invalid, /unavailable API version/)
    profiles.mount([1])
    expect { profiles.register(2, go: go_config) }.to raise_error(described_class::Invalid, /already mounted/)
  end

  it 'loads Rust TOML configuration and rejects a snapshot bound to another API version at mount' do
    generator = Module.new
    generator.const_set(:VERSION, '0.30.0')
    documentation = Class.new
    generator.const_set(:Documentation, documentation)
    stub_const('HaveAPI::RustClient', generator)
    toml = Module.new
    stub_const('Tomlrb', toml)
    config_path = File.join(directory, 'generator.toml')
    File.write(config_path, 'fixture config')
    File.write(description_path, JSON.generate({ api_version: '2' }))
    config = { 'crate_name' => 'widget-client', 'crate_version' => '1.2.3' }
    allow(toml).to receive(:load_file).with(config_path).and_return(config)
    allow(profiles).to receive(:require).with('haveapi/rust_client/documentation').and_return(true)
    allow(documentation).to receive(:new).and_return(adapter)
    profiles.register(1, rust: { snapshot_path: description_path, generator_config_path: config_path, generator_version: '0.30.0' })
    expect(documentation).to have_received(:new).with(snapshot: { 'api_version' => '2' }, config:)
    expect(profiles.for_version(1).fetch(:rust)).to have_attributes(package_name: 'widget-client', package_version: '1.2.3')
    expect { profiles.mount([1]) }.to raise_error(described_class::Invalid, /snapshot API version mismatch/)
  end
end
