require 'spec_helper'
require 'haveapi/rust_client/documentation'

describe HaveAPI::RustClient::Documentation do
  include RustGeneratorFixtures

  let(:schema) { snapshot }
  let(:config) do
    { 'crate_name' => 'fixture-client', 'crate_version' => '0.1.0', 'license' => 'MIT',
      'edition' => '2024', 'rust_version' => '1.95', 'rustfmt_version' => 'not invoked' }
  end
  let(:source) { { git: 'https://example.test/fixture-client', rev: 'a1' * 20 } }
  let(:context) do
    Struct.new(:version, :base_url, :description, :resource_path, :action_name, :sample, :detail).new(
      '1.0', 'https://visible.example.test/', schema.fetch('description'), ['widget'], 'update',
      { path_params: [1], request: { name: 'visible' }, response: { id: 1 } }, :thorough
    )
  end

  def automatic(**options)
    described_class.from_description(description: schema.fetch('description'), api_version: '1.0',
                                     protocol_version: '2.0', mount_path: '/', crate_name: 'fixture-client', **options)
  end

  def render(adapter, mode = :async, kind = :init, **options)
    adapter.render(kind:, context:, mode:, **options).fetch(:code)
  end

  it 'builds pure IR directly without generator construction, acquisition, generation or process calls' do
    allow(HaveAPI::RustClient::Generator).to receive(:new)
    allow(HaveAPI::RustClient::Snapshot).to receive(:fetch)
    allow(Open3).to receive(:capture3)
    allow(File).to receive(:write)
    expect(render(automatic, :async, :example)).to include('.send().await?')
    expect(render(described_class.new(snapshot: schema, config:), :blocking, :example)).to include('.send()?')
    expect(HaveAPI::RustClient::Generator).not_to have_received(:new)
    expect(HaveAPI::RustClient::Snapshot).not_to have_received(:fetch)
    expect(Open3).not_to have_received(:capture3)
    expect(File).not_to have_received(:write)
  end

  %i[async blocking].each do |mode|
    it "keeps an omitted #{mode} registry version nil and prints valid package-manager commands" do
      adapter = automatic
      expect(adapter.instance_variable_get(:@crate_version)).to be_nil
      code = render(adapter, mode)
      command = '// cargo add fixture-client'
      command += ' --features blocking' if mode == :blocking
      expect(code.lines.first.strip).to eq(command)
      expect(code).to include('// cargo add serde_json')
      expect(code.include?('// cargo add tokio --features macros,rt-multi-thread')).to eq(mode == :async)
      expect(code).not_to include('latest', '0.0.0', 'version =', 'haveapi.invalid', 'server-documentation')
      expect(code).to include('https://visible.example.test/')
    end

    it "keeps explicit #{mode} versions under ordinary Cargo requirement semantics" do
      code = render(automatic(crate_version: '0.1.0'), mode)
      expect(code).to include('fixture-client = { version = "0.1.0"')
      expect(code).not_to include('version = "=0.1.0"')
      expect(code.include?('features = ["blocking"]')).to eq(mode == :blocking)
    end

    it "uses Git/revision metadata without inventing a #{mode} crate version" do
      code = render(automatic(source:), mode)
      dependency = code.lines.first.delete_prefix('// Cargo.toml: ')
      parsed = Tomlrb.parse(dependency).fetch('fixture-client')
      expect(parsed).to include('git' => source[:git], 'rev' => source[:rev])
      expect(parsed.has_key?('version')).to be(false)
      expect(parsed['features']).to eq(mode == :blocking ? ['blocking'] : nil)
      expect(code).not_to include('// cargo add fixture-client')
    end

    it "adds a supplied #{mode} version as a Git package constraint" do
      code = render(automatic(source:, crate_version: '0.1.0'), mode)
      parsed = Tomlrb.parse(code.lines.first.delete_prefix('// Cargo.toml: ')).fetch('fixture-client')
      expect(parsed).to include('git' => source[:git], 'rev' => source[:rev], 'version' => '0.1.0')
    end

    it "renders legacy, saved-inline and automatic models equivalently for #{mode}" do
      adapters = [described_class.new(snapshot: schema, config:),
                  described_class.from_snapshot(snapshot: schema, crate_name: 'fixture-client', crate_version: '0.1.0'),
                  automatic(crate_version: '0.1.0')]
      %i[init example auth].each do |kind|
        options = kind == :auth ? { auth_method: :basic, auth_description: {} } : {}
        expect(adapters.map { |adapter| render(adapter, mode, kind, **options) }.uniq.length).to eq(1)
      end
    end
  end

  it 'uses the mounted request context while keeping structural URL and capture labels private' do
    schema['mount_path'] = '/mounted/api/'
    schema['source_url'] = 'https://saved.example.test/mounted/api/v1.0/'
    schema['description']['help'] = '/mounted/api/v1.0/'
    schema['description']['resources']['widget']['actions']['update']['path'] = '/mounted/api/v1.0/widgets/{widget_id}'
    context.base_url = 'https://visible.example.test/mounted/api/'
    adapter = described_class.from_description(description: schema['description'], api_version: '1.0',
                                               protocol_version: '2.0', mount_path: '/mounted/api/', crate_name: 'fixture-client')
    code = render(adapter, :async, :example)
    expect(code).to include('https://visible.example.test/mounted/api/', 'api.widget().update("1")')
    expect(code).not_to include('haveapi.invalid', 'server-documentation', 'saved.example.test')
    expect(schema['source_url']).to eq('https://saved.example.test/mounted/api/v1.0/')
  end

  it 'copies and freezes package/source/model state without freezing caller-owned values' do
    name = +'fixture-client'
    version = +'0.1.0'
    original = Marshal.load(Marshal.dump(source))
    adapter = described_class.from_snapshot(snapshot: schema, crate_name: name, crate_version: version, source:)
    source[:git].replace('https://changed.example.test/')
    source[:rev].replace('b' * 40)
    name.replace('changed-client')
    version.replace('9.0.0')
    expect(render(adapter)).to include(original[:git], original[:rev], 'fixture-client', 'version = "0.1.0"')
    expect(adapter.resolve(resource_path: ['widget'], action_name: 'update')).to be_frozen
    expect(schema).not_to be_frozen
    expect(source).not_to be_frozen
  end

  it 'does not expose hidden fields/defaults or drop unsupported inputs with automatic models' do
    fields = schema['description']['resources']['widget']['actions']['update']['input']['parameters']
    fields['private'] = parameter(default: 'hidden-value')
    adapter = automatic
    context.description = Marshal.load(Marshal.dump(context.description))
    context.description['resources']['widget']['actions']['update']['input']['parameters'].delete('private')
    expect(render(adapter, :async, :example)).not_to include('private', 'hidden-value')
    context.sample[:request][:private] = 'not-visible-secret'
    result = adapter.render(kind: :example, context:, mode: :async)
    expect(result[:status]).to eq(:limitation)
    expect(result.inspect).not_to include('private', 'hidden-value', 'not-visible-secret')
  end

  it 'uses the complete canonical collision scope for automatic descriptions' do
    fields = schema['description']['resources']['widget']['actions']['update']['input']['parameters']
    fields['name!'] = parameter
    fields['name?'] = parameter
    expect { automatic }.to raise_error(HaveAPI::RustClient::Error, /collision/)
  end

  it 'validates conflicting metadata during automatic construction' do
    meta = schema['description']['resources']['widget']['actions']['update']['meta']
    meta['global'] = { 'output' => io('count' => parameter('Integer')) }
    meta['object'] = { 'output' => io('count' => parameter('String')) }
    expect { automatic }.to raise_error(HaveAPI::RustClient::Error, /inconsistent metadata/)
  end

  it 'retains full legacy packaging validation and rejects conflicting identity forms' do
    [{ 'license' => 'Apache-2.0' }, { 'edition' => '2021' }, { 'rust_version' => '1.94' },
     { 'rustfmt_version' => '' }, { 'crate_version' => nil }, { 'extra' => true }].each do |invalid|
      expect { described_class.new(snapshot: schema, config: config.merge(invalid)) }.to raise_error(HaveAPI::RustClient::Error)
    end
    expect { described_class.new(snapshot: schema, config:, crate_name: 'other') }
      .to raise_error(HaveAPI::RustClient::Error, /conflicting/)
  end

  ['', 'latest', 'v1', '1.2', "0.1.0\n", '0.1.0"; command'].each do |version|
    it "rejects malformed explicit package version #{version.inspect}" do
      expect { automatic(crate_version: version) }.to raise_error(HaveAPI::RustClient::Error, %r{crate name/version})
    end
  end

  it 'retains import normalization and reserved-name handling' do
    expect(render(described_class.from_snapshot(snapshot: schema, crate_name: 'async'))).to include('use r#async::Client;')
    %w[crate self super].each do |name|
      expect { described_class.from_snapshot(snapshot: schema, crate_name: name) }.to raise_error(HaveAPI::RustClient::Error, /imported/)
    end
    expect { automatic(crate_name: 'injected"; command') }.to raise_error(HaveAPI::RustClient::Error)
  end

  it 'renders source values as TOML data and never executes source text' do
    url = 'https://example.test/sdk$(command)%22%5C%3Cscript%3E'
    code = render(automatic(source: { 'git' => url, 'rev' => 'A' * 40 }))
    expect(Tomlrb.parse(code.lines.first.delete_prefix('// Cargo.toml: ')).dig('fixture-client', 'git')).to eq(url)
    expect(code).not_to include('haveapi.invalid')
  end

  [[], {}, { git: 'https://example.test/sdk' }, { git: 'https://example.test/sdk', rev: 'main' },
   { git: 'https://example.test/sdk', rev: 'a' * 40, branch: 'main' },
   { git: 'http://example.test/sdk', rev: 'a' * 40 },
   { git: 'https://user:secret@example.test/sdk', rev: 'a' * 40 },
   { git: 'https://example.test/sdk?token=secret', rev: 'a' * 40 },
   { git: 'https://example.test/sdk#secret', rev: 'a' * 40 },
   { git: "https://example.test/sdk\nsecret", rev: 'a' * 40 },
   { git: 'https://example.test/sdk"; secret', rev: 'a' * 40 },
   { git: :not_a_url, rev: 'a' * 40 }, { git: 'https://example.test/sdk', rev: nil }].each_with_index do |invalid, index|
    it "rejects unsupported source metadata #{index + 1} without exposing its contents" do
      expect { automatic(source: invalid) }.to raise_error(HaveAPI::RustClient::Error, 'invalid Rust SDK source')
    end
  end
end
