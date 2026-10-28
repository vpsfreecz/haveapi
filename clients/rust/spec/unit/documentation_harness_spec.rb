require 'spec_helper'
require_relative '../documentation/run'

describe RustDocumentationAcceptance do
  include RustGeneratorFixtures

  let(:config) do
    { 'crate_name' => 'fixture-client', 'crate_version' => '0.1.0', 'license' => 'MIT',
      'edition' => '2024', 'rust_version' => '1.95', 'rustfmt_version' => 'not invoked' }
  end
  let(:schema) { snapshot }
  let(:adapter) { HaveAPI::RustClient::Documentation.new(snapshot: schema, config:).freeze }
  let(:profile) { Struct.new(:language, :adapter).new(:rust, adapter).freeze }
  let(:context) do
    HaveAPI::ClientExample::Context.new(
      detail: :thorough,
      version: '1.0', host: 'example.test', base_url: 'https://example.test/', version_url: 'https://example.test/v1.0/',
      description: schema.fetch('description'), resource_path: ['widget'], action_name: 'update',
      sample: { path_params: [1], request: { name: 'actual rendered source' }, response: { id: 1 } }, profile:
    )
  end

  def renderer
    HaveAPI::ClientExamples::RustAsyncClient
  end

  it 'extracts the actual registered renderer output and keeps it intact' do
    direct = renderer.render(:example, context:).fetch(:code)
    extracted = described_class.source(renderer, :example, context)
    expect(extracted).to eq(direct)
    assertion = 'assert_eq!(response.output.id, Some(1));'
    checked = RustDocumentationCases.assert_output(extracted, assertion)
    expect(checked.sub("    #{assertion}\n", '')).to eq(direct)
  end

  it 'combines exact auth builder and action body without rewriting the request' do
    auth = described_class.source(renderer, :auth, context, auth_method: :basic,
                                                            auth_description: schema['description']['authentication']['basic'])
    action = described_class.source(renderer, :example, context)
    composed = RustDocumentationCases.compose_authentication(auth, action)
    expect(composed).to include('.basic_auth(std::env::var("HAVEAPI_USER")?, std::env::var("HAVEAPI_PASSWORD")?)')
    expect(composed).to include(action.split("        .build()?;\n", 2).last.split('    Ok(())', 2).first.rstrip)
    expect(composed.scan('#[tokio::main]').length).to eq(1)
  end

  it 'wraps a simple fragment with separately rendered authentication without changing its source' do
    auth = described_class.source(renderer, :auth, context, auth_method: :basic,
                                                            auth_description: schema['description']['authentication']['basic'])
    fragment = described_class.source(renderer, :example, context.with(detail: :simple))
    composed = RustDocumentationCases.compose_fragment(auth, fragment)
    expect(composed).to include(fragment, 'Client::builder', '.basic_auth(')
    expect(composed.scan('api.widget().update').length).to eq(1)
  end

  it 'resolves fixture canonical names independently of Rust normalization' do
    entry = { resource: ['Widget'], action: 'Update', sample: { request: {} } }
    result = RustDocumentationCases.context_for(context, entry)
    expect(result.resource_path).to eq(['widget'])
    expect(result.action_name).to eq('update')
    expect(result.sample).to eq(request: {})
  end

  it 'refuses a limitation before writing a purported executable program' do
    expect do
      described_class.source(renderer, :example, context.with(sample: { request: { unknown: true }, path_params: [1] }))
    end.to raise_error(RuntimeError, /Unexpected Rust documentation limitation/)
  end

  it 'makes no server or compiler calls when loaded as a quick contract spec' do
    expect(defined?(RustClientIntegration)).to eq('constant')
    expect(RustDocumentationCases.cases.map { |entry| entry.fetch(:name) })
      .to include('null', 'omitted', 'list', 'nested', 'failure', 'state')
  end

  it 'keeps real renderer output for legacy, unversioned snapshot and Git profile installation forms' do
    sources = described_class.profile_initializations(renderer, context, snapshot: schema, config:)
    expect(sources.keys).to eq(%w[legacy_profile saved_profile git_profile git_versioned_profile])
    expect(sources.fetch('legacy_profile')).to eq(renderer.render(:init, context:).fetch(:code))
    expect(sources.fetch('saved_profile')).to start_with("// cargo add fixture-client\n")
    expect(sources.fetch('git_profile')).to include('git = "https://example.test/documentation-fixture"', "rev = \"#{'a' * 40}\"")
    expect(sources.fetch('git_profile')).not_to include('version =')
    expect(sources.fetch('git_versioned_profile')).to include('version = "0.1.0"')
    expect(sources.values).to all(include('use fixture_client::Client;', 'https://example.test/'))
    sources.each_value { |source| expect(source).not_to include('haveapi.invalid', 'version = "latest"') }
  end

  it 'retains per-mount fixture inputs, owned generated source and emitted programs without build artifacts' do
    Dir.mktmpdir('rust-documentation-evidence-') do |directory|
      root = File.join(directory, 'crate')
      FileUtils.mkdir_p(File.join(root, 'src/generated'))
      FileUtils.mkdir_p(File.join(root, 'examples'))
      FileUtils.mkdir_p(File.join(root, 'target/debug'))
      {
        'Cargo.toml' => 'fixture manifest', 'Cargo.lock' => 'fixture dependency graph',
        'src/generated/.haveapi-generated.json' => '{"owner":"haveapi-rust-client"}',
        'src/generated/mod.rs' => 'owned generated source', 'examples/async_init.rs' => 'emitted example',
        'target/debug/cache' => 'exclude build output'
      }.each { |path, data| File.write(File.join(root, path), data) }
      tools = { 'msrv_rustc' => { 'executable' => '/fixture/rustc', 'version' => 'rustc 1.95.0' } }
      %w[/ /mounted/api/].each do |mount|
        destination = described_class.evidence_directory(File.join(directory, 'evidence'), mount)
        described_class.retain_evidence(root:, destination:, snapshot: schema, config:, tools:)
        expect(JSON.parse(File.read(File.join(destination, 'snapshot.json')))).to eq(schema)
        expect(Tomlrb.load_file(File.join(destination, 'generator.toml'))).to eq(config)
        expect(File.read(File.join(destination, 'Cargo.lock'))).to eq('fixture dependency graph')
        expect(File.read(File.join(destination, 'src/generated/.haveapi-generated.json'))).to include('haveapi-rust-client')
        expect(File.read(File.join(destination, 'examples/async_init.rs'))).to eq('emitted example')
        expect(JSON.parse(File.read(File.join(destination, 'tools.json')))).to eq(tools)
        expect(File.exist?(File.join(destination, 'target'))).to be(false)
      end
    end
  end

  it 'keeps evidence optional and refuses to mix artifacts into an earlier mount receipt' do
    expect(described_class.evidence_directory(nil, '/')).to be_nil
    expect(described_class.retain_evidence(root: '/unused', destination: nil, snapshot: nil, config: nil, tools: nil)).to be_nil
    Dir.mktmpdir('rust-documentation-evidence-') do |directory|
      described_class.evidence_directory(directory, '/')
      expect { described_class.evidence_directory(directory, '/') }.to raise_error(Errno::EEXIST)
    end
  end

  it 'retains available artifacts when a fixture stops before generation or lock resolution' do
    Dir.mktmpdir('rust-documentation-evidence-') do |directory|
      destination = described_class.evidence_directory(directory, '/')
      described_class.retain_evidence(root: File.join(directory, 'missing'), destination:, snapshot: schema, config: nil, tools: {})
      expect(File.exist?(File.join(destination, 'snapshot.json'))).to be(true)
      expect(File.exist?(File.join(destination, 'Cargo.lock'))).to be(false)
    end
  end
end
