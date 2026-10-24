require 'spec_helper'
require 'tmpdir'

describe HaveAPI::ClientExample::Profiles do
  let(:profiles) { described_class.new }
  let(:adapter) do
    Class.new do
      def resolve(**); end
      def render(**); end
    end.new
  end
  let(:directory) { Dir.mktmpdir('haveapi-doc-profiles-') }
  let(:description) { { resources: {}, authentication: {}, meta: { namespace: '_meta' } } }
  let(:server) { instance_double(HaveAPI::Server, versions: [1], root: '/', describe_version: description) }

  def description_path
    File.join(directory, 'description.json')
  end

  def config_path
    File.join(directory, 'generator.toml')
  end

  def go_config
    { import_path: 'example.test/widget/client', module_version: 'v1.2.3', description_path:, generator_version: HaveAPI::VERSION }
  end

  def rust_config
    { snapshot_path: description_path, generator_config_path: config_path, generator_version: HaveAPI::VERSION }
  end

  def generator_config
    { 'crate_name' => 'widget-client', 'crate_version' => '1.2.3' }
  end

  before do
    File.write(description_path, JSON.generate(description))
    File.write(config_path, 'fixture config')
  end

  after { FileUtils.remove_entry(directory) }

  def install_go_adapter(version: HaveAPI::VERSION)
    generator = Module.new
    generator.const_set(:VERSION, version)
    documentation = Class.new
    generator.const_set(:Documentation, documentation)
    stub_const('HaveAPI::GoClient', generator)
    allow(profiles).to receive(:require).with('haveapi/go_client/documentation').and_return(true)
    allow(documentation).to receive(:new).and_return(adapter)
    documentation
  end

  def install_rust_adapter(factories: true)
    generator = Module.new
    generator.const_set(:VERSION, HaveAPI::VERSION)
    documentation = Class.new
    generator.const_set(:Documentation, documentation)
    generator.const_set(:Generator, Class.new)
    generator.const_set(:Model, Module.new)
    generator.const_set(:Snapshot, Class.new)
    stub_const('HaveAPI::RustClient', generator)
    stub_const('Tomlrb', Module.new)
    allow(Tomlrb).to receive(:load_file).with(config_path).and_return(generator_config)
    allow(profiles).to receive(:require).with('haveapi/rust_client/documentation').and_return(true)
    allow(documentation).to receive(:new).and_return(adapter)
    if factories
      allow(documentation).to receive_messages(from_description: adapter, from_snapshot: adapter)
      allow(documentation).to receive(:validate_source) { |source| source }
      allow(HaveAPI::RustClient::Generator).to receive(:validate_config)
      allow(HaveAPI::RustClient::Model).to receive(:validate_package)
    end
    documentation
  end

  def finalize
    profiles.mount([1])
    profiles.finalize(server)
  end

  it 'needs no optional generator or schema when profiles are absent' do
    allow(profiles).to receive(:require).and_raise('Unexpected optional dependency')
    finalize
    expect(profiles).not_to have_received(:require)
    expect(server).not_to have_received(:describe_version)
    expect(profiles.for_version(1)).to eq({})
    expect(profiles.for_version(1)).to be_frozen
  end

  it 'loads an explicit saved adapter once without rereading it during finalization' do
    documentation = install_go_adapter
    profiles.register(1, go: go_config)
    expect(profiles.for_version(1)).to be_empty
    File.unlink(description_path)
    finalize
    profile = profiles.for_version(1).fetch(:go)
    expect(profile).to have_attributes(language: :go, package_name: 'example.test/widget/client', package_version: 'v1.2.3')
    expect(profile).to be_frozen
    expect(profile.adapter).to equal(adapter)
    expect(documentation).to have_received(:new).once.with(description: JSON.parse(JSON.generate(description)), import_path: 'example.test/widget/client', module_version: 'v1.2.3')
    expect(server).not_to have_received(:describe_version)
    expect(profile).not_to respond_to(:description_path)
  end

  it 'defaults the generator version and defers automatic Go without inventing an SDK version' do
    documentation = install_go_adapter
    config = { import_path: 'example.test/widget/client' }
    profiles.register(1, go: config)
    config[:import_path].replace('changed.test/client')
    expect(documentation).not_to have_received(:new)
    finalize
    profile = profiles.for_version(1).fetch(:go)
    expect(profile.package_name).to eq('example.test/widget/client')
    expect(profile.package_version).to be_nil
    expect(documentation).to have_received(:new).with(description: JSON.parse(JSON.generate(description)), import_path: 'example.test/widget/client', module_version: nil)
    expect(server).to have_received(:describe_version).once
  end

  it 'permits nil SDK versions and retains explicitly pinned generator versions' do
    documentation = install_go_adapter(version: '0.29.0')
    profiles.register(1, go: go_config.merge(module_version: nil, generator_version: '0.29.0'))
    finalize
    expect(profiles.for_version(1).fetch(:go).package_version).to be_nil
    expect(documentation).to have_received(:new).with(description: anything, import_path: anything, module_version: nil)
  end

  it 'rejects unknown languages, malformed fields and unsafe package configuration' do
    expect { profiles.register(1, python: {}) }.to raise_error(described_class::Invalid, /Unknown/)
    expect { profiles.register(1, go: go_config.merge(unexpected: 'value')) }.to raise_error(described_class::Invalid, /fields/)
    expect { profiles.register(1, go: go_config.merge(import_path: "example.test/\nsource")) }.to raise_error(described_class::Invalid, /package/)
    ['latest', '', 1, false].each do |value|
      expect { profiles.register(1, go: go_config.merge(module_version: value)) }.to raise_error(described_class::Invalid, /package/)
    end
    expect { profiles.register(1, go: go_config.merge(generator_version: nil)) }.to raise_error(described_class::Invalid)
    expect { profiles.register(1, go: go_config.merge(generator_version: 'latest')) }.to raise_error(described_class::Invalid, /generator version/)
    expect { profiles.register(1, go: {}) }.to raise_error(described_class::Invalid, /package/)
  end

  it 'rejects missing adapters, mismatched generator versions and missing files at registration' do
    allow(profiles).to receive(:require).and_raise(LoadError)
    expect { profiles.register(1, go: go_config) }.to raise_error(described_class::Invalid, /not installed/)
    install_go_adapter
    expect { profiles.register(1, go: go_config.merge(generator_version: '0.29.0')) }.to raise_error(described_class::Invalid, /version mismatch/)
    expect { profiles.register(1, go: go_config.merge(description_path: 'relative.json')) }.to raise_error(described_class::Invalid, /absolute local/)
  end

  it 'checks the configured adapter interface' do
    documentation = install_go_adapter
    allow(documentation).to receive(:new).and_return(Object.new)
    expect { profiles.register(1, go: go_config) }.to raise_error(described_class::Invalid, /adapter interface/)
  end

  it 'does not leave a partially registered language set after an invalid second profile' do
    install_go_adapter
    expect { profiles.register(1, go: go_config, rust: { unknown: 'field' }) }.to raise_error(described_class::Invalid)
    profiles.register(1, go: go_config)
    finalize
    expect(profiles.for_version(1).keys).to eq([:go])
  end

  it 'rejects duplicates and registration after mounting starts' do
    install_go_adapter
    profiles.register(1, go: go_config)
    expect { profiles.register('1', go: go_config) }.to raise_error(described_class::Invalid, /Duplicate/)
    profiles.mount([1])
    expect { profiles.register(2, go: go_config) }.to raise_error(described_class::Invalid, /already mounted/)
    profiles.finalize(server)
    expect { profiles.finalize(server) }.to raise_error(described_class::Invalid, /not ready/)
  end

  it 'rejects profiles for an unavailable version' do
    install_go_adapter
    profiles.register(1, go: go_config)
    expect { profiles.mount([2]) }.to raise_error(described_class::Invalid, /unavailable API version/)
    expect(profiles.for_version(1)).to be_empty
  end

  it 'preserves legacy Rust construction even without the new factories' do
    documentation = install_rust_adapter(factories: false)
    File.write(description_path, JSON.generate({ api_version: '1' }))
    profiles.register(1, rust: rust_config)
    finalize
    expect(documentation).to have_received(:new).with(snapshot: { 'api_version' => '1' }, config: generator_config)
    expect(profiles.for_version(1).fetch(:rust)).to have_attributes(package_name: 'widget-client', package_version: '1.2.3')
  end

  it 'rejects a saved Rust snapshot for a different selected API version at mount' do
    install_rust_adapter
    File.write(description_path, JSON.generate({ api_version: '2' }))
    profiles.register(1, rust: rust_config)
    expect { profiles.mount([1]) }.to raise_error(described_class::Invalid, /snapshot API version mismatch/)
    expect(profiles.for_version(1)).to be_empty
  end

  it 'validates inline Rust identity and source before building from the mounted description' do
    documentation = install_rust_adapter
    source = { git: 'https://example.test/widget-client', rev: 'a' * 40 }
    profiles.register(1, rust: { crate_name: 'widget-client', source: })
    expect(HaveAPI::RustClient::Model).to have_received(:validate_package).with(crate_name: 'widget-client', crate_version: nil)
    expect(documentation).to have_received(:validate_source).with(source)
    expect(documentation).not_to have_received(:from_description)
    finalize
    expect(documentation).to have_received(:from_description).with(description: anything, api_version: '1', protocol_version: HaveAPI::PROTOCOL_VERSION,
                                                                   mount_path: '/', crate_name: 'widget-client', crate_version: nil, source:)
    expect(profiles.for_version(1).fetch(:rust).package_version).to be_nil
  end

  it 'supports an inline Rust identity with a saved snapshot and optional explicit SDK version' do
    documentation = install_rust_adapter
    snapshot = { 'api_version' => '1' }
    File.write(description_path, JSON.generate(snapshot))
    profiles.register(1, rust: { snapshot_path: description_path, crate_name: 'widget-client', crate_version: '1.2.3' })
    finalize
    expect(documentation).to have_received(:from_snapshot).with(snapshot:, crate_name: 'widget-client', crate_version: '1.2.3', source: nil)
    expect(server).not_to have_received(:describe_version)
  end

  it 'validates full legacy TOML before using it with an automatic Rust description' do
    documentation = install_rust_adapter
    snapshot = { 'api_version' => '1' }
    allow(HaveAPI::RustClient::Snapshot).to receive(:from_description).and_return(snapshot)
    profiles.register(1, rust: { generator_config_path: config_path })
    expect(HaveAPI::RustClient::Generator).to have_received(:validate_config).with(generator_config)
    finalize
    expect(HaveAPI::RustClient::Snapshot).to have_received(:from_description).with(description: anything, api_version: '1', protocol_version: HaveAPI::PROTOCOL_VERSION,
                                                                                   mount_path: '/', source_url: 'https://haveapi.invalid/v1/', profile: 'server-documentation')
    expect(documentation).to have_received(:new).with(snapshot:, config: generator_config)
  end

  it 'rejects automatic and inline modes when an older Rust generator lacks their factories' do
    install_rust_adapter(factories: false)
    expect { profiles.register(1, rust: { generator_config_path: config_path }) }.to raise_error(described_class::Invalid, /does not support/)
    expect { profiles.register(1, rust: { crate_name: 'widget-client', snapshot_path: description_path }) }.to raise_error(described_class::Invalid, /does not support/)
  end

  it 'rejects conflicting Rust identities and unknown source profile fields' do
    install_rust_adapter
    expect { profiles.register(1, rust: rust_config.merge(crate_name: 'widget-client')) }.to raise_error(described_class::Invalid, /Conflicting/)
    expect { profiles.register(1, rust: rust_config.merge(crate_version: nil)) }.to raise_error(described_class::Invalid, /Conflicting/)
    expect { profiles.register(1, rust: { crate_name: 'widget-client', branch: 'main' }) }.to raise_error(described_class::Invalid, /fields/)
  end

  it 'captures one private structural schema per version shared by automatic profiles' do
    go = install_go_adapter
    rust = install_rust_adapter
    profiles.register(1, go: { import_path: 'example.test/client' }, rust: { crate_name: 'widget-client' })
    finalize
    expect(server).to have_received(:describe_version).once do |context|
      expect(context).to have_attributes(server:, version: 1, current_user: nil, endpoint: false, doc: true)
    end
    expect(go).to have_received(:new).with(description: anything, import_path: anything, module_version: nil)
    expect(rust).to have_received(:from_description).with(description: anything, api_version: '1', protocol_version: anything, mount_path: '/', crate_name: anything, crate_version: nil, source: nil)
  end

  it 'publishes no partial profiles and hides private diagnostics when finalization fails' do
    install_go_adapter
    rust = install_rust_adapter
    allow(rust).to receive(:from_description).and_raise('HIDDEN_SCHEMA_DEFAULT')
    profiles.register(1, go: { import_path: 'example.test/client' }, rust: { crate_name: 'widget-client' })
    profiles.mount([1])
    expect { profiles.finalize(server) }.to raise_error(described_class::Invalid, 'Configured documentation client schema or configuration is invalid')
    expect(profiles.for_version(1)).to be_empty
    expect { profiles.register(1, go: go_config) }.to raise_error(described_class::Invalid, /already mounted/)
  end
end
