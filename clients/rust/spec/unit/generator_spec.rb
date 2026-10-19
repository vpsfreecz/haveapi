require_relative '../spec_helper'

RSpec.describe HaveAPI::RustClient::Generator do
  include RustGeneratorFixtures

  let(:dir) { Dir.mktmpdir('haveapi-rust-unit-') }
  let(:output) { File.join(dir, 'generated') }

  after { FileUtils.remove_entry(dir) }

  def files
    Dir.glob(File.join(output, '**/*'), File::FNM_DOTMATCH).select { |path| File.file?(path) }.to_h do |path|
      [path.delete_prefix(output), [File.binread(path), File.mtime(path)]]
    end
  end

  it 'generates identical offline files after shuffled object keys and never writes during check' do
    schema = snapshot
    generator = described_class.new(schema:, config: generator_config)
    generator.generate(output: output)
    before = files
    shuffled = JSON.parse(JSON.generate(schema)).transform_values { |value| value.is_a?(Hash) ? value.to_a.reverse.to_h : value }
    described_class.new(schema: shuffled, config: generator_config).generate(output: output, check: true)
    expect(files).to eq(before)
    manifest = JSON.parse(File.read(File.join(output, described_class::OWNER_FILE)))
    runtime = File.join(described_class::ROOT, 'runtime/src/runtime/mod.rs')
    expect(File.binread(File.join(output, 'runtime/mod.rs'))).to eq(File.binread(runtime))
    expect(manifest.fetch('schema_sha256')).to eq(HaveAPI::RustClient::Snapshot.sha256(schema))
  end

  it 'reports stale trees read-only then removes obsolete owned files on regeneration' do
    schema = snapshot(actions: { 'update' => action, 'show' => action(method: 'GET') })
    generator = described_class.new(schema:, config: generator_config)
    generator.generate(output: output)
    before = files
    schema.fetch('description').fetch('resources').fetch('widget').fetch('actions').delete('show')
    newer = described_class.new(schema:, config: generator_config)
    expect { newer.generate(output: output, check: true) }.to raise_error(HaveAPI::RustClient::Error, /stale/)
    expect(files).to eq(before)
    sentinel = File.join(dir, 'handwritten.rs')
    File.write(sentinel, 'preserved')
    newer.generate(output: output)
    expect(File.exist?(File.join(output, 'resources/widget/show.rs'))).to be(false)
    expect(File.read(sentinel)).to eq('preserved')
  end

  it 'refuses foreign files and symlinked destinations without changing them' do
    generator = described_class.new(schema: snapshot, config: generator_config)
    Dir.mkdir(output)
    File.write(File.join(output, 'handwritten.rs'), 'preserved')
    expect { generator.generate(output: output) }.to raise_error(HaveAPI::RustClient::Error, /ownership/)
    expect(File.read(File.join(output, 'handwritten.rs'))).to eq('preserved')
    linked = File.join(dir, 'linked')
    File.symlink(output, linked)
    expect { generator.generate(output: linked) }.to raise_error(HaveAPI::RustClient::Error, /symlink/)
  end

  it 'rejects extra unowned files and symlinks inside an owned tree' do
    generator = described_class.new(schema: snapshot, config: generator_config)
    generator.generate(output: output)
    File.write(File.join(output, 'foreign.rs'), 'preserved')
    expect { generator.generate(output: output) }.to raise_error(HaveAPI::RustClient::Error, /not owned/)
    File.unlink(File.join(output, 'foreign.rs'))
    File.symlink('/tmp', File.join(output, 'escape'))
    expect { generator.generate(output: output) }.to raise_error(HaveAPI::RustClient::Error, /symlink/)
  end

  it 'rejects an unpinned formatter before creating output' do
    generator = described_class.new(schema: snapshot, config: generator_config.merge('rustfmt_version' => 'wrong'))
    expect { generator.generate(output: output) }.to raise_error(HaveAPI::RustClient::Error, /rustfmt version/)
    expect(File.exist?(output)).to be(false)
  end

  it 'preserves named empty outputs and a distinct true no-output action' do
    schema = snapshot(actions: {
      'empty' => action(output: io({})),
      'none' => action.merge('output' => { 'parameters' => {} }),
      'list' => action(output: io({}, layout: 'object_list'))
    })
    described_class.new(schema:, config: generator_config).generate(output: output)
    base = File.join(output, 'resources/widget')
    expect(File.read(File.join(base, 'empty.rs'))).to include('allow_empty_response: true', 'pub struct Output')
    expect(File.read(File.join(base, 'none.rs'))).to include('output: None')
    expect(File.read(File.join(base, 'list.rs'))).to include('allow_empty_response: false')
  end
end
