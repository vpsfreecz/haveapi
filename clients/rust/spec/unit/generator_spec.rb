require_relative '../spec_helper'

RSpec.describe HaveAPI::RustClient::Generator do
  include RustGeneratorFixtures

  let(:dir) { Dir.mktmpdir('haveapi-rust-unit-') }
  let(:output) { File.join(dir, 'generated') }
  let(:config) { generator_config }

  after { FileUtils.remove_entry(dir) }

  def files
    Dir.glob(File.join(output, '**/*'), File::FNM_DOTMATCH).select { |path| File.file?(path) }.to_h do |path|
      [path.delete_prefix(output), [File.binread(path), File.mtime(path)]]
    end
  end

  it 'binds the loaded shared schema source identity into generator provenance' do
    before = described_class.new(schema: snapshot, config: config).send(:generator_digest)
    identity = HaveAPI::Schema.source_identity
    allow(HaveAPI::Schema).to receive(:source_identity).and_return(identity.merge('source_sha256' => '0' * 64))
    expect(described_class.new(schema: snapshot, config: config).send(:generator_digest)).not_to eq(before)
    allow(HaveAPI::Schema).to receive(:source_identity).and_return(identity.merge('version' => '999.0'))
    expect(described_class.new(schema: snapshot, config: config).send(:generator_digest)).not_to eq(before)
  end

  it 'generates identical offline files after shuffled object keys and never writes during check' do
    schema = snapshot
    generator = described_class.new(schema:, config: config)
    generator.generate(output: output)
    before = files
    shuffled = JSON.parse(JSON.generate(schema)).transform_values { |value| value.is_a?(Hash) ? value.to_a.reverse.to_h : value }
    described_class.new(schema: shuffled, config: config).generate(output: output, check: true)
    expect(files).to eq(before)
    manifest = JSON.parse(File.read(File.join(output, described_class::OWNER_FILE)))
    runtime = File.join(described_class::ROOT, 'runtime/src/runtime/mod.rs')
    expect(File.binread(File.join(output, 'runtime/mod.rs'))).to eq(File.binread(runtime))
    expect(manifest.fetch('schema_sha256')).to eq(HaveAPI::RustClient::Snapshot.sha256(schema))
  end

  it 'reports stale trees read-only then removes obsolete owned files on regeneration' do
    schema = snapshot(actions: { 'update' => action, 'show' => action(method: 'GET') })
    generator = described_class.new(schema:, config: config)
    generator.generate(output: output)
    before = files
    schema.fetch('description').fetch('resources').fetch('widget').fetch('actions').delete('show')
    newer = described_class.new(schema:, config: config)
    expect { newer.generate(output: output, check: true) }.to raise_error(HaveAPI::RustClient::Error, /stale/)
    expect(files).to eq(before)
    sentinel = File.join(dir, 'handwritten.rs')
    File.write(sentinel, 'preserved')
    newer.generate(output: output)
    expect(File.exist?(File.join(output, 'resources/widget/show.rs'))).to be(false)
    expect(File.read(sentinel)).to eq('preserved')
  end

  it 'refuses foreign files and symlinked destinations without changing them' do
    generator = described_class.new(schema: snapshot, config: config)
    Dir.mkdir(output)
    File.write(File.join(output, 'handwritten.rs'), 'preserved')
    expect { generator.generate(output: output) }.to raise_error(HaveAPI::RustClient::Error, /ownership/)
    expect(File.read(File.join(output, 'handwritten.rs'))).to eq('preserved')
    linked = File.join(dir, 'linked')
    File.symlink(output, linked)
    expect { generator.generate(output: linked) }.to raise_error(HaveAPI::RustClient::Error, /symlink/)
  end

  it 'rejects extra unowned files and symlinks inside an owned tree' do
    generator = described_class.new(schema: snapshot, config: config)
    generator.generate(output: output)
    File.write(File.join(output, 'foreign.rs'), 'preserved')
    expect { generator.generate(output: output) }.to raise_error(HaveAPI::RustClient::Error, /not owned/)
    File.unlink(File.join(output, 'foreign.rs'))
    File.symlink('/tmp', File.join(output, 'escape'))
    expect { generator.generate(output: output) }.to raise_error(HaveAPI::RustClient::Error, /symlink/)
  end

  it 'rejects a mismatched formatter without creating or modifying output' do
    schema = snapshot
    generator = described_class.new(schema:, config: config.merge('rustfmt_version' => 'wrong'))
    expect { generator.generate(output: output) }.to raise_error(HaveAPI::RustClient::Error, /rustfmt version/)
    expect(File.exist?(output)).to be(false)

    described_class.new(schema:, config: config).generate(output: output)
    before = files
    expect { generator.generate(output: output) }.to raise_error(HaveAPI::RustClient::Error, /rustfmt version/)
    expect(files).to eq(before)
  end

  it 'gets fixture configuration from the selected formatter executable' do
    formatter = File.join(dir, 'fixture formatter')
    File.write(formatter, "#!/bin/sh\nprintf '%s\\n' 'rustfmt fixture'\n")
    File.chmod(0o755, formatter)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('RUSTFMT', 'rustfmt').and_return(formatter)

    expect(config.fetch('rustfmt_version')).to eq('rustfmt fixture')
  end

  it 'rejects a failed fixture formatter probe even when it prints version text' do
    formatter = File.join(dir, 'fixture formatter')
    File.write(formatter, "#!/bin/sh\nprintf '%s\\n' 'rustfmt fixture'\nexit 1\n")
    File.chmod(0o755, formatter)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('RUSTFMT', 'rustfmt').and_return(formatter)

    expect { config }.to raise_error(RuntimeError, /Unable to determine fixture rustfmt version/)
  end

  it 'preserves named empty outputs and a distinct true no-output action' do
    schema = snapshot(actions: {
      'empty' => action(output: io({})),
      'none' => action.merge('output' => { 'parameters' => {} }),
      'list' => action(output: io({}, layout: 'object_list'))
    })
    described_class.new(schema:, config: config).generate(output: output)
    base = File.join(output, 'resources/widget')
    expect(File.read(File.join(base, 'empty.rs'))).to include('allow_empty_response: true', 'pub struct Output')
    expect(File.read(File.join(base, 'none.rs'))).to include('output: None')
    expect(File.read(File.join(base, 'list.rs'))).to include('allow_empty_response: false')
  end

  it 'scopes naming exceptions to resource modules and accessors with double underscores' do
    schema = snapshot
    schema['description']['resources']['widget']['resources']['task'] = {
      'resources' => {}, 'actions' => { 'show' => action(path: '/v1.0/widgets/{widget_id}/tasks/{task_id}', method: 'GET') }
    }
    schema['description']['resources']['widget_task'] = {
      'resources' => {}, 'actions' => { 'show' => action(path: '/v1.0/widget_tasks/{task_id}', method: 'GET') }
    }
    schema['description']['authentication']['token'] = {
      'http_header' => 'X-Token', 'resources' => {
        'token' => { 'resources' => {}, 'actions' => { 'show' => action(path: '/_auth/token/tokens', method: 'GET') } }
      }
    }
    generator = described_class.new(schema:, config:)
    generator.generate(output:)
    before = files
    generator.generate(output:, check: true)
    expect(files).to eq(before)
    modules = File.read(File.join(output, 'resources/mod.rs'))
    expect(modules).to include("#[allow(non_snake_case)]\npub mod widget__task;")
    expect(modules).to include("#[allow(non_snake_case)]\npub mod authentication__token__token;")
    expect(modules).to include('pub mod widget_task;', 'pub mod widget;')
    expect(modules.scan('#[allow(non_snake_case)]').length).to eq(2)
    nested = File.read(File.join(output, 'resources/widget__task/mod.rs'))
    expect(nested).to include("#[allow(non_snake_case)]\n    pub fn widget__task(&self, widget_id: impl ToString)")
    expect(nested).to match(/pub fn show\(\s*&self,\s*task_id: impl ToString,?\s*\)/)
    expect(nested.scan('#[allow(non_snake_case)]').length).to eq(1)
    ordinary = File.read(File.join(output, 'resources/widget_task/mod.rs'))
    expect(ordinary).to include('pub fn widget_task(&self)')
    expect(ordinary).not_to include('allow(non_snake_case)')
    action_source = File.read(File.join(output, 'resources/widget__task/show.rs'))
    expect(action_source).to include('path: "v1.0/widgets/{widget_id}/tasks/{task_id}"')
    expect(action_source).not_to include('allow(non_snake_case)')
    expect(File.read(File.join(output, 'mod.rs'))).not_to include('allow(non_snake_case)', 'allow(warnings)')
  end
end
