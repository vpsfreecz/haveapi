require_relative '../spec_helper'

RSpec.describe HaveAPI::TypeScriptClient::Generator do
  include TypeScriptFixtures

  before do
    emitter = Class.new
    stub_const('HaveAPI::TypeScriptClient::Emitter', emitter)
    emitter_files('index.ts' => "export {};\n", 'old.ts' => "export {};\n")
  end

  let(:nested_files) do
    {
      'index.ts' => "export {};\n",
      'api.ts' => "export const api = true;\n",
      'runtime.ts' => "export interface RequestExecutor {}\n",
      'types.ts' => "export type { Widget } from './resources/widget/resource.js';\n",
      'resources/widget/resource.ts' => "export interface Widget {}\n",
      'resources/widget/actions/update.ts' => "export const update = true;\n",
      'resources/widget/resources/child/resource.ts' => "export interface Child {}\n",
      'resources/widget/resources/child/actions/show.ts' => "export const show = true;\n"
    }
  end

  def emitter_files(files)
    allow(HaveAPI::TypeScriptClient::Emitter).to receive(:new).and_return(double(files:))
  end

  def output_state(output)
    Dir.glob('**/*', File::FNM_DOTMATCH, base: output).reject { |path| %w[. ..].include?(File.basename(path)) }.sort.to_h do |path|
      full = File.join(output, path)
      stat = File.stat(full)
      [path, [stat.ftype, stat.mtime, File.file?(full) ? File.binread(full) : nil]]
    end.merge('.' => File.stat(output).mtime)
  end

  def generator
    instance = described_class.new(schema: snapshot)
    allow(instance).to receive(:require_relative).with('emitter')
    instance
  end

  it 'binds the loaded shared schema source identity into generator provenance' do
    before = described_class.source_digest
    identity = HaveAPI::Schema.source_identity
    allow(HaveAPI::Schema).to receive(:source_identity).and_return(identity.merge('source_sha256' => '0' * 64))
    expect(described_class.source_digest).not_to eq(before)
    allow(HaveAPI::Schema).to receive(:source_identity).and_return(identity.merge('version' => '999.0'))
    expect(described_class.source_digest).not_to eq(before)
  end

  it 'generates deterministic owned output and removes stale owned files' do
    Dir.mktmpdir do |root|
      output = File.join(root, 'src/generated')
      generator.generate(output:)
      manifest = JSON.parse(File.read(File.join(output, described_class::OWNER_FILE)))
      expect(manifest.fetch('coverage')).to include('application_action_count' => 1, 'authentication_action_count' => 0)
      before = File.stat(File.join(output, 'index.ts')).mtime
      expect(generator.generate(output:, check: true)).to be(true)
      expect(File.stat(File.join(output, 'index.ts')).mtime).to eq(before)
      allow(HaveAPI::TypeScriptClient::Emitter).to receive(:new).and_return(double(files: { 'index.ts' => "export const changed = true;\n" }))
      expect { generator.generate(output:, check: true) }.to raise_error(HaveAPI::TypeScriptClient::Error, /stale/)
      expect(File.read(File.join(output, 'index.ts'))).to eq("export {};\n")
      generator.generate(output:)
      expect(File.exist?(File.join(output, 'old.ts'))).to be(false)
    end
  end

  it 'leaves missing destinations and their parents untouched in check mode' do
    emitter_files(nested_files)
    Dir.mktmpdir do |root|
      expect { generator.generate(output: File.join(root, 'missing/src/generated'), check: true) }
        .to raise_error(HaveAPI::TypeScriptClient::Error, /stale/)
      expect(Dir.children(root)).to be_empty
    end
  end

  it 'installs and hashes nested modules without rewriting an identical tree' do
    emitter_files(nested_files)
    Dir.mktmpdir do |root|
      output = File.join(root, 'src/generated')
      generator.generate(output:)
      manifest = JSON.parse(File.read(File.join(output, described_class::OWNER_FILE)))
      expect(manifest.fetch('files')).to eq(nested_files.transform_values { |content| Digest::SHA256.hexdigest(content) })
      nested_files.each { |path, content| expect(File.binread(File.join(output, path))).to eq(content) }
      before = output_state(output)
      expect(generator.generate(output:, check: true)).to be(true)
      expect(generator.generate(output:)).to be(true)
      expect(output_state(output)).to eq(before)
    end
  end

  it 'detects nested drift without changing files, directories or the manifest' do
    emitter_files(nested_files)
    Dir.mktmpdir do |root|
      output = File.join(root, 'src/generated')
      generator.generate(output:)
      File.write(File.join(output, 'resources/widget/resources/child/actions/show.ts'), "export const show = false;\n")
      before = output_state(output)
      expect { generator.generate(output:, check: true) }.to raise_error(HaveAPI::TypeScriptClient::Error, /stale/)
      expect(output_state(output)).to eq(before)
    end
  end

  it 'removes a stale nested subtree while preserving its live resource and action' do
    emitter_files(nested_files)
    Dir.mktmpdir do |root|
      output = File.join(root, 'src/generated')
      generator.generate(output:)
      retained = nested_files.reject { |path, _content| path.start_with?('resources/widget/resources/') }
      emitter_files(retained)
      before = output_state(output)
      expect { generator.generate(output:, check: true) }.to raise_error(HaveAPI::TypeScriptClient::Error, /stale/)
      expect(output_state(output)).to eq(before)
      generator.generate(output:)
      expect(File.exist?(File.join(output, 'resources/widget/resources'))).to be(false)
      retained.each { |path, content| expect(File.binread(File.join(output, path))).to eq(content) }
      manifest = JSON.parse(File.read(File.join(output, described_class::OWNER_FILE)))
      expect(manifest.fetch('files').keys).to match_array(retained.keys)
      expect(generator.generate(output:, check: true)).to be(true)
    end
  end

  it 'refuses nested foreign files before rewriting or removing owned modules' do
    emitter_files(nested_files)
    Dir.mktmpdir do |root|
      output = File.join(root, 'src/generated')
      generator.generate(output:)
      File.write(File.join(output, 'resources/widget/resources/child/handwritten.ts'), 'keep')
      emitter_files('index.ts' => "export const changed = true;\n")
      before = output_state(output)
      [true, false].each do |check|
        expect { generator.generate(output:, check:) }.to raise_error(HaveAPI::TypeScriptClient::Error, /not owned.*handwritten/)
        expect(output_state(output)).to eq(before)
      end
    end
  end

  it 'refuses a symlink in place of an owned nested action without changing its target' do
    emitter_files(nested_files)
    Dir.mktmpdir do |root|
      output = File.join(root, 'src/generated')
      generator.generate(output:)
      manifest = File.binread(File.join(output, described_class::OWNER_FILE))
      target = File.join(root, 'outside.ts')
      File.write(target, 'keep')
      path = File.join(output, 'resources/widget/actions/update.ts')
      File.unlink(path)
      File.symlink(target, path)
      [true, false].each do |check|
        expect { generator.generate(output:, check:) }.to raise_error(HaveAPI::TypeScriptClient::Error, /symlink/)
        expect(File.symlink?(path)).to be(true)
        expect(File.read(target)).to eq('keep')
        expect(File.binread(File.join(output, described_class::OWNER_FILE))).to eq(manifest)
      end
    end
  end

  it 'refuses a symlink at a planned nested parent before creating output outside the tree' do
    Dir.mktmpdir do |root|
      output = File.join(root, 'src/generated')
      generator.generate(output:)
      manifest = File.binread(File.join(output, described_class::OWNER_FILE))
      target = File.join(root, 'outside')
      FileUtils.mkdir_p(target)
      FileUtils.mkdir_p(File.join(output, 'resources'))
      path = File.join(output, 'resources/widget')
      File.symlink(target, path)
      emitter_files(nested_files)
      [true, false].each do |check|
        expect { generator.generate(output:, check:) }.to raise_error(HaveAPI::TypeScriptClient::Error, /symlink/)
        expect(Dir.children(target)).to be_empty
        expect(File.symlink?(path)).to be(true)
        expect(File.binread(File.join(output, described_class::OWNER_FILE))).to eq(manifest)
      end
    end
  end

  it 'migrates a flat manifest to nested modules and replaces the monolithic API content' do
    emitter_files(
      'index.ts' => nested_files.fetch('index.ts'),
      'api.ts' => "export const flatAction = true;\n",
      'runtime.ts' => nested_files.fetch('runtime.ts')
    )
    Dir.mktmpdir do |root|
      output = File.join(root, 'src/generated')
      generator.generate(output:)
      emitter_files(nested_files)
      before = output_state(output)
      expect { generator.generate(output:, check: true) }.to raise_error(HaveAPI::TypeScriptClient::Error, /stale/)
      expect(output_state(output)).to eq(before)
      generator.generate(output:)
      expect(File.binread(File.join(output, 'api.ts'))).to eq(nested_files.fetch('api.ts'))
      manifest = JSON.parse(File.read(File.join(output, described_class::OWNER_FILE)))
      expect(manifest.fetch('files').keys).to match_array(nested_files.keys)
      expect(generator.generate(output:, check: true)).to be(true)
    end
  end

  it 'refuses foreign files, symlinks and unsafe output paths' do
    Dir.mktmpdir do |root|
      output = File.join(root, 'src/generated')
      FileUtils.mkdir_p(output)
      File.write(File.join(output, 'handwritten.ts'), 'keep')
      expect { generator.generate(output:) }.to raise_error(HaveAPI::TypeScriptClient::Error, /ownership/)
      File.unlink(File.join(output, 'handwritten.ts'))
      generator.generate(output:)
      File.write(File.join(output, 'handwritten.ts'), 'keep')
      expect { generator.generate(output:) }.to raise_error(HaveAPI::TypeScriptClient::Error, /not owned/)
      File.unlink(File.join(output, 'handwritten.ts'))
      File.symlink(root, File.join(output, 'link'))
      expect { generator.generate(output:) }.to raise_error(HaveAPI::TypeScriptClient::Error, /symlink/)
      expect { generator.generate(output: root) }.to raise_error(HaveAPI::TypeScriptClient::Error, %r{src/generated})
    end
  end

  it 'validates all emitted paths before touching output' do
    allow(HaveAPI::TypeScriptClient::Emitter).to receive(:new).and_return(double(files: { 'index.ts' => "export {};\n", '../foreign.ts' => "bad\n" }))
    Dir.mktmpdir do |root|
      expect { generator.generate(output: File.join(root, 'src/generated')) }.to raise_error(HaveAPI::TypeScriptClient::Error, /unsafe/)
      expect(Dir.children(root)).to be_empty
    end
  end

  it 'rejects query object-input metadata before touching output or invoking the emitter' do
    schema = snapshot
    fixture_action(schema)['method'] = 'GET'
    fixture_action(schema)['meta']['object'] = { 'input' => io('revision' => parameter('Integer', required: true)) }
    Dir.mktmpdir do |root|
      expect { described_class.new(schema:).generate(output: File.join(root, 'src/generated')) }
        .to raise_error(HaveAPI::TypeScriptClient::Error, %r{widget/update/meta/object/input})
      expect(Dir.children(root)).to be_empty
      expect(HaveAPI::TypeScriptClient::Emitter).not_to have_received(:new)
    end
  end
end
