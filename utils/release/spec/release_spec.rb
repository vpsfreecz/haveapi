require 'rspec'
require_relative '../publish'
require_relative '../workflow'

RSpec.describe HaveAPI::Release do
  def root
    File.expand_path('../../..', __dir__)
  end
  let(:artifacts) { HaveAPI::Release::Artifacts.new(root) }

  let(:tmp) { Dir.mktmpdir('haveapi-release-spec-') }

  after { FileUtils.remove_entry(tmp) }

  def git(directory, *args)
    HaveAPI::Release.capture('git', *args, chdir: directory)
  end

  def commit(directory, message)
    path = File.join(tmp, 'commit-message')
    File.write(path, "#{message}\n")
    git(directory, '-c', 'user.name=Release Test', '-c', 'user.email=release@example.invalid', 'commit', '-F', path)
  end

  def tar(path, files)
    File.open(path, 'wb') do |file|
      Gem::Package::TarWriter.new(file) do |writer|
        files.each { |name, content| writer.add_file_simple(name, 0o644, content.bytesize) { |f| f.write(content) } }
      end
    end
  end

  def npm_fixture
    {
      'package/package.json' => JSON.generate({ name: 'haveapi-client', version: artifacts.version,
                                                repository: { url: 'https://github.com/vpsfreecz/haveapi' }, main: 'dist/haveapi-client.js', types: 'dist/types/haveapi.d.ts' }),
      'package/dist/haveapi-client.js' => "function Client() {} Client.Version = '#{artifacts.version}'; module.exports = { Client, CallbackClient: Client, AsyncClient: function AsyncClient() {} };",
      'package/dist/types/haveapi.d.ts' => "export * from './client';\n",
      'package/dist/types/client.d.ts' => <<~TS,
        export declare class Client {
          constructor(url: string);
          setLanguage(language: string): void;
          setup(callback: (client: Client, ok: boolean) => void): void;
        }
        export { Client as CallbackClient };
        export interface RequestResult<T> { data: T; }
        export declare class AsyncClient {
          constructor(url: string);
          request<T>(spec: { method: string; path: string }): Promise<RequestResult<T>>;
        }
        export declare class AsyncError { constructor(kind: string, message: string); }
      TS
      'package/README.md' => 'Client usage',
      'package/doc-async-client.md' => 'Async client usage',
      'package/doc-async-resources.md' => 'Async resources',
      'package/LICENSE.txt' => 'MIT license'
    }
  end

  def npm_tar(files)
    path = File.join(tmp, "haveapi-client-#{artifacts.version}.tgz")
    tar(File.join(tmp, 'npm.tar'), files)
    Zlib::GzipWriter.open(path) { |gzip| gzip.write(File.binread(File.join(tmp, 'npm.tar'))) }
    File.binwrite(File.join(tmp, 'haveapi-client.js'), files.fetch('package/dist/haveapi-client.js'))
    path
  end

  def stub_npm_install(archive)
    allow(described_class).to receive(:run).and_raise('Unexpected npm smoke command')
    allow(described_class).to receive(:run).with({ 'NODE_PATH' => nil }, 'node', any_args, chdir: kind_of(String)).and_call_original
    allow(described_class).to receive(:run).with({ 'NODE_PATH' => nil }, 'npm', 'install', '--ignore-scripts', '--no-audit', '--no-fund', archive, chdir: kind_of(String)) do |*_args, **options|
      consumer = options.fetch(:chdir)
      expect(consumer).not_to start_with(root)
      expect(JSON.parse(File.read(File.join(consumer, 'package.json'))).fetch('private')).to be(true)
      artifacts.tar_files(archive, gzip: true).each do |name, (content, _mode)|
        path = File.join(consumer, 'node_modules/haveapi-client', name.delete_prefix('package/'))
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, content)
      end
    end
  end

  def fixture_manifest
    allow(artifacts).to receive(:source).and_return('a' * 40)
    allow(artifacts).to receive(:inspect_packages)
    artifacts.names.each { |name| File.write(File.join(tmp, name), name) }
    manifest = {
      schema: 1, source: artifacts.source, version: artifacts.version, tag: artifacts.tag,
      run_id: ENV.fetch('GITHUB_RUN_ID', 'local'), files: artifacts.names.to_h { |name| [name, Digest::SHA256.file(File.join(tmp, name)).hexdigest] }
    }
    File.write(File.join(tmp, 'release-manifest.json'), JSON.generate(manifest))
    manifest
  end

  describe 'metadata and artifacts' do
    it 'validates the maintained source versions without reading Elixir' do
      expect { artifacts.check }.not_to raise_error
    end

    it 'rejects a mismatched authored JavaScript client version' do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(File.join(root, 'clients/js/src/haveapi/client.ts')).and_return("Client.Version = '999.0.0';")
      expect { artifacts.check }.to raise_error(HaveAPI::Release::Error, %r{Version mismatch in clients/js/src/haveapi/client\.ts})
    end

    ['', 'packages'].each do |location|
      %w[name version].each do |field|
        it "rejects mismatched npm lock #{location.empty? ? 'top-level' : 'package root'} #{field}" do
          path = File.join(root, 'clients/js/package-lock.json')
          lock = JSON.parse(File.read(path))
          entry = location.empty? ? lock : lock.fetch('packages').fetch('')
          entry[field] = 'wrong'
          allow(File).to receive(:read).and_call_original
          allow(File).to receive(:read).with(path).and_return(JSON.generate(lock))
          expect { artifacts.check }.to raise_error(HaveAPI::Release::Error, %r{mismatch in clients/js/package-lock})
        end
      end
    end

    it 'updates both npm lock roots without changing any nested dependency bytes in a disposable version bump' do
      copy = File.join(tmp, 'source')
      git(root, 'ls-files', '-z').split("\0").each do |name|
        destination = File.join(copy, name)
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(File.join(root, name), destination)
      end
      path = File.join(copy, 'clients/js/package-lock.json')
      before = File.read(path)
      old_lock = JSON.parse(before)
      described_class.capture('make', 'version', 'VERSION=999.0.0', chdir: copy)
      after = File.read(path)
      expected = old_lock.merge('version' => '999.0.0', 'packages' => old_lock.fetch('packages').merge('' => old_lock.fetch('packages').fetch('').merge('version' => '999.0.0')))
      expect(JSON.parse(after)).to eq(expected)
      dependency_start = "\t\t\"node_modules/"
      expect(after[after.index(dependency_start)..]).to eq(before[before.index(dependency_start)..])
      File.write(File.join(copy, 'CHANGELOG.md'), "# 2099-01-01 - version 999.0.0\n\n## Changed\nDisposable fixture.\n")
      candidate = described_class::Artifacts.new(copy)
      expect { candidate.check }.not_to raise_error
      expected['packages']['']['version'] = artifacts.version
      File.write(path, JSON.generate(expected))
      expect { candidate.check }.to raise_error(HaveAPI::Release::Error, %r{mismatch in clients/js/package-lock})
    end

    it 'rejects a version tag that differs from VERSION' do
      expect { artifacts.check_tag('v999.0.0') }.to raise_error(HaveAPI::Release::Error, /Tag must be/)
    end

    it 'rejects a missing changelog entry' do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(File.join(root, 'CHANGELOG.md')).and_return('# unrelated')
      expect { artifacts.check }.to raise_error(HaveAPI::Release::Error, /no entry/)
    end

    it 'rejects a mismatched dependency before building' do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(File.join(root, 'servers/ruby/haveapi.gemspec')).and_return("s.add_dependency 'haveapi-client', '~> 999.0.0'")
      expect { artifacts.check }.to raise_error(HaveAPI::Release::Error, /Dependency mismatch/)
    end

    it 'accepts retained hashes and rejects changed bytes' do
      fixture_manifest
      expect(artifacts.verify(tmp).fetch('source')).to eq('a' * 40)
      File.write(File.join(tmp, 'haveapi-client.js'), 'different bytes')
      expect { artifacts.verify(tmp) }.to raise_error(HaveAPI::Release::Error, /checksum mismatch/)
    end

    it 'rejects a manifest from another source commit' do
      manifest = fixture_manifest
      manifest[:source] = 'b' * 40
      File.write(File.join(tmp, 'release-manifest.json'), JSON.generate(manifest))
      expect { artifacts.verify(tmp) }.to raise_error(HaveAPI::Release::Error, /this source/)
    end

    it 'rejects artifacts from a different workflow run' do
      manifest = fixture_manifest
      manifest[:run_id] = 'another-run'
      File.write(File.join(tmp, 'release-manifest.json'), JSON.generate(manifest))
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('GITHUB_RUN_ID').and_return('123')
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('GITHUB_RUN_ID').and_return('123')
      expect { artifacts.verify(tmp) }.to raise_error(HaveAPI::Release::Error, /different workflow run/)
    end

    it 'rejects archive paths that escape the extraction directory' do
      path = File.join(tmp, 'unsafe.tar')
      tar(path, { '../outside' => 'data' })
      expect { artifacts.tar_files(path) }.to raise_error(HaveAPI::Release::Error, /Unsafe archive/)
    end

    it 'rejects symlinks in an archive' do
      path = File.join(tmp, 'symlink.tar')
      File.open(path, 'wb') { |file| Gem::Package::TarWriter.new(file) { |writer| writer.add_symlink('src', '/tmp', 0o777) } }
      expect { artifacts.tar_files(path) }.to raise_error(HaveAPI::Release::Error, /Unsupported archive/)
    end
  end

  describe 'npm package contract' do
    it 'accepts the retained bundle, declarations and owning documentation' do
      npm_tar(npm_fixture)
      expect { artifacts.inspect_npm(tmp) }.not_to raise_error
    end

    %w[main types].each do |field|
      it "rejects the wrong package #{field} entry" do
        files = npm_fixture
        metadata = JSON.parse(files.fetch('package/package.json'))
        metadata[field] = 'src/haveapi.ts'
        files['package/package.json'] = JSON.generate(metadata)
        npm_tar(files)
        expect { artifacts.inspect_npm(tmp) }.to raise_error(HaveAPI::Release::Error, /Wrong npm main or types/)
      end
    end

    %w[README.md doc-async-client.md doc-async-resources.md LICENSE.txt dist/types/haveapi.d.ts].each do |name|
      it "rejects missing #{name}" do
        npm_tar(npm_fixture.reject { |path, _content| path == "package/#{name}" })
        expect { artifacts.inspect_npm(tmp) }.to raise_error(HaveAPI::Release::Error, /missing or has empty #{Regexp.escape(name)}/)
      end
    end

    it 'rejects an empty transitive declaration' do
      npm_tar(npm_fixture.merge('package/dist/types/client.d.ts' => ' '))
      expect { artifacts.inspect_npm(tmp) }.to raise_error(HaveAPI::Release::Error, /Empty npm declaration/)
    end

    it 'rejects a bundle different from the standalone browser artifact' do
      npm_tar(npm_fixture)
      File.write(File.join(tmp, 'haveapi-client.js'), 'different bundle')
      expect { artifacts.inspect_npm(tmp) }.to raise_error(HaveAPI::Release::Error, /does not contain the built bundle/)
    end

    it 'runs package-name CommonJS and the pinned compiler against an isolated installed fixture' do
      stub_npm_install(npm_tar(npm_fixture))
      expect { artifacts.smoke_npm(tmp) }.not_to raise_error
      expect(described_class).to have_received(:run).with({ 'NODE_PATH' => nil }, 'npm', 'install', any_args, chdir: kind_of(String))
    end

    it 'rejects a missing transitive declaration through the real compiler' do
      stub_npm_install(npm_tar(npm_fixture.except('package/dist/types/client.d.ts')))
      expect { artifacts.smoke_npm(tmp) }.to raise_error(HaveAPI::Release::Error, %r{failed to compile:.*Cannot find module '\./client'}m)
    end

    it 'rejects a declaration reference outside the installed package' do
      outside = File.join(tmp, 'outside.d.ts')
      File.write(outside, 'export {};')
      files = npm_fixture
      files['package/dist/types/haveapi.d.ts'] = "/// <reference path=\"#{outside}\" />\n#{files.fetch('package/dist/types/haveapi.d.ts')}"
      stub_npm_install(npm_tar(files))
      expect { artifacts.smoke_npm(tmp) }.to raise_error(HaveAPI::Release::Error, /resolved types outside the installed package/)
    end
  end

  describe 'artifact reuse' do
    let(:workflow) { HaveAPI::Release::Workflow }

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('GITHUB_RUN_ID').and_return('123')
      allow(ENV).to receive(:fetch).with('GITHUB_REPOSITORY').and_return('vpsfreecz/haveapi')
      allow(ENV).to receive(:fetch).with('GITHUB_RUN_ATTEMPT').and_return('2')
    end

    it 'restores the original immutable artifact on reruns' do
      allow(workflow).to receive(:api).and_return([{ 'artifacts' => [{ 'id' => 42, 'name' => 'release-123', 'expired' => false }] }])
      expect(workflow.artifact_id).to eq('42')
    end

    it 'allows retrying a build that failed before artifact upload' do
      allow(workflow).to receive(:api).and_return([{ 'artifacts' => [] }], [{ 'jobs' => [{ 'steps' => [{ 'name' => 'Retain release artifacts', 'conclusion' => 'skipped' }] }] }])
      expect(workflow.artifact_id).to eq('')
    end

    it 'refuses to rebuild when a previous successful upload has disappeared' do
      allow(workflow).to receive(:api).and_return([{ 'artifacts' => [] }], [{ 'jobs' => [{ 'steps' => [{ 'name' => 'Retain release artifacts', 'conclusion' => 'success' }] }] }])
      expect { workflow.artifact_id }.to raise_error(HaveAPI::Release::Error, /Original artifacts are missing/)
    end

    it 'refuses to rebuild expired artifacts' do
      allow(workflow).to receive(:api).and_return([{ 'artifacts' => [{ 'id' => 42, 'name' => 'release-123', 'expired' => true }] }])
      expect { workflow.artifact_id }.to raise_error(HaveAPI::Release::Error, /expired/)
    end

    it 'rejects an environment without required reviewers' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('HAVEAPI_RELEASE_ENABLED').and_return('true')
      allow(workflow).to receive(:api).and_return([{ 'protection_rules' => [] }])
      expect { workflow.check_activation }.to raise_error(HaveAPI::Release::Error, /required reviewers/)
    end
  end

  describe 'existing registry versions' do
    let(:publisher) { HaveAPI::Release::Publisher.new(artifacts, tmp) }

    before { fixture_manifest }

    def pypi_metadata(names = artifacts.python_names)
      {
        'info' => { 'name' => 'haveapi-client', 'version' => artifacts.version },
        'urls' => names.map do |name|
          { 'filename' => name, 'digests' => { 'sha256' => Digest::SHA256.file(File.join(tmp, name)).hexdigest } }
        end
      }
    end

    it 'accepts only the original Python artifact hashes from PyPI' do
      allow(publisher).to receive(:registry_json).and_return(pypi_metadata)
      expect(publisher.pypi_files.keys).to eq(artifacts.python_names)
      mismatched = pypi_metadata
      mismatched['urls'][0]['digests']['sha256'] = 'different'
      allow(publisher).to receive(:registry_json).and_return(mismatched)
      expect { publisher.pypi_files }.to raise_error(HaveAPI::Release::Error, /PyPI file differs/)
    end

    it 'refuses unexpected Python files and duplicate filenames' do
      metadata = pypi_metadata
      metadata['urls'] << metadata['urls'].first
      allow(publisher).to receive(:registry_json).and_return(metadata)
      expect { publisher.pypi_files }.to raise_error(HaveAPI::Release::Error, /unexpected files/)
    end

    it 'stages only missing original Python files after all registry preflights' do
      allow(publisher).to receive(:with_php_mirror).and_yield('mirror', {})
      allow(publisher).to receive(:preflight_php)
      allow(publisher).to receive(:gem_present?)
      allow(publisher).to receive(:npm_present?)
      allow(publisher).to receive(:registry_json).and_return(pypi_metadata([artifacts.python_names.first]))
      allow(ENV).to receive(:fetch).and_call_original
      output = File.join(tmp, 'output')
      allow(ENV).to receive(:fetch).with('GITHUB_OUTPUT').and_return(output)
      publisher.prepare_pypi
      expect(publisher).to have_received(:preflight_php).with('mirror').ordered
      HaveAPI::Release::GEMS.each_key { |name| expect(publisher).to have_received(:gem_present?).with(name).ordered }
      expect(publisher).to have_received(:npm_present?).ordered
      staged = File.join(tmp, 'python-publish')
      expect(Dir.children(staged)).to eq([artifacts.python_names.last])
      expect(File.binread(File.join(staged, artifacts.python_names.last))).to eq(File.binread(File.join(tmp, artifacts.python_names.last)))
      expect(File.read(output)).to eq("publish=true\n")
    end

    it 'does not write registries or the PHP mirror while Python publication is incomplete' do
      allow(publisher).to receive(:registry_json).and_return(nil)
      allow(publisher).to receive(:with_php_mirror).and_yield('mirror', {})
      allow(publisher).to receive(:preflight_php)
      allow(publisher).to receive(:publish_registries)
      allow(publisher).to receive(:sync_php)
      expect { publisher.publish }.to raise_error(HaveAPI::Release::Error, /PyPI publication is incomplete/)
      expect(publisher).to have_received(:preflight_php).with('mirror')
      expect(publisher).not_to have_received(:publish_registries)
      expect(publisher).not_to have_received(:sync_php)
    end

    it 'accepts a gem only when its registry checksum matches the retained gem' do
      name = "haveapi-client-#{artifacts.version}.gem"
      allow(publisher).to receive(:registry_json).and_return({ 'sha' => Digest::SHA256.file(File.join(tmp, name)).hexdigest })
      expect(publisher.gem_present?('haveapi-client')).to be(true)
      allow(publisher).to receive(:registry_json).and_return({ 'sha' => 'different' })
      expect { publisher.gem_present?('haveapi-client') }.to raise_error(HaveAPI::Release::Error, /differs/)
    end

    it 'accepts npm only when identity and tarball integrity match' do
      path = File.join(tmp, "haveapi-client-#{artifacts.version}.tgz")
      metadata = { 'name' => 'haveapi-client', 'version' => artifacts.version, 'dist' => { 'integrity' => "sha512-#{Digest::SHA512.file(path).base64digest}" } }
      allow(publisher).to receive(:registry_json).and_return(metadata)
      expect(publisher.npm_present?).to be(true)
      metadata['dist']['integrity'] = 'sha512-different'
      expect { publisher.npm_present? }.to raise_error(HaveAPI::Release::Error, /differs/)
    end

    it 'checks for conflicting versions before making any registry write' do
      allow(publisher).to receive(:gem_present?).and_return(false)
      allow(publisher).to receive(:npm_present?).and_raise(HaveAPI::Release::Error, 'Existing npm version differs')
      allow(described_class).to receive(:run)
      expect { publisher.publish_registries }.to raise_error(HaveAPI::Release::Error, /differs/)
      expect(described_class).not_to have_received(:run)
    end
  end

  describe 'GitHub release preparation' do
    let(:publisher) { HaveAPI::Release::Publisher.new(artifacts, tmp) }
    let(:draft) { { 'id' => 123, 'tag_name' => 'untagged-pending-release', 'draft' => true, 'assets' => [] } }
    let(:query_command) do
      ['gh', 'api', 'graphql', '-f', a_string_matching(/\Aquery=.*repository\(owner: "vpsfreecz", name: "haveapi"\).*release\(tagName: \$tag\).*databaseId/m), '-f', "tag=#{artifacts.tag}"]
    end

    def github_response(value, error: '')
      [JSON.generate(value), error, instance_double(Process::Status, success?: error.empty?)]
    end

    def github_lookup(release)
      github_response({ 'data' => { 'repository' => { 'release' => release } } })
    end

    before do
      fixture_manifest
      allow(described_class).to receive(:run)
      allow(Open3).to receive(:capture3).with(*query_command).and_return(github_lookup({ 'databaseId' => 123 }))
      allow(Open3).to receive(:capture3).with('gh', 'api', 'repos/vpsfreecz/haveapi/releases/123').and_return(github_response(draft))
    end

    it 'resolves an existing draft by its pending tag and uploads retained artifacts' do
      publisher.prepare_github
      expect(described_class).not_to have_received(:run).with('gh', 'release', 'create', any_args)
      (artifacts.names + ['release-manifest.json']).each do |name|
        expect(described_class).to have_received(:run).with('gh', 'release', 'upload', artifacts.tag, File.join(tmp, name), '--repo', 'vpsfreecz/haveapi')
      end
    end

    it 'finds a newly created draft by its pending tag before uploading artifacts' do
      allow(Open3).to receive(:capture3).with(*query_command).and_return(github_lookup(nil), github_lookup({ 'databaseId' => 123 }))
      expect { publisher.prepare_github }.not_to raise_error
      expect(described_class).to have_received(:run).with('gh', 'release', 'create', artifacts.tag, '--repo', 'vpsfreecz/haveapi', '--verify-tag', '--draft', '--title', "HaveAPI #{artifacts.version}", '--notes-file', File.join(tmp, 'release-notes.md'))
      expect(described_class).to have_received(:run).with('gh', 'release', 'upload', artifacts.tag, File.join(tmp, 'release-manifest.json'), '--repo', 'vpsfreecz/haveapi')
    end

    it 'also retrieves an already published release by its resolved ID' do
      published = draft.merge('draft' => false, 'tag_name' => artifacts.tag)
      allow(Open3).to receive(:capture3).with('gh', 'api', 'repos/vpsfreecz/haveapi/releases/123').and_return(github_response(published))
      expect(publisher.github_release).to eq(published)
    end

    it 'treats only an explicit null release as absent' do
      allow(Open3).to receive(:capture3).with(*query_command).and_return(github_lookup(nil))
      expect(publisher.github_release).to be_nil
      expect(Open3).not_to have_received(:capture3).with('gh', 'api', 'repos/vpsfreecz/haveapi/releases/123')
    end

    [403, 404].each do |status|
      it "keeps HTTP #{status} GraphQL failures visible without creating a draft" do
        allow(Open3).to receive(:capture3).with(*query_command).and_return(github_response({}, error: "gh: query failed (HTTP #{status})"))
        expect { publisher.prepare_github }.to raise_error(HaveAPI::Release::Error, /GitHub release query failed.*#{status}/)
        expect(described_class).not_to have_received(:run)
      end

      it "keeps HTTP #{status} release-ID failures visible without creating a draft" do
        allow(Open3).to receive(:capture3).with('gh', 'api', 'repos/vpsfreecz/haveapi/releases/123').and_return(github_response({}, error: "gh: query failed (HTTP #{status})"))
        expect { publisher.prepare_github }.to raise_error(HaveAPI::Release::Error, /GitHub release query failed.*#{status}/)
        expect(described_class).not_to have_received(:run)
      end
    end

    it 'reports an absent post-create lookup before uploading any artifacts' do
      allow(Open3).to receive(:capture3).with(*query_command).and_return(github_lookup(nil))
      expect { publisher.prepare_github }.to raise_error(HaveAPI::Release::Error, /Created GitHub draft was not found/)
      expect(described_class).not_to have_received(:run).with('gh', 'release', 'upload', any_args)
    end
  end

  describe 'PHP synchronization' do
    let(:publisher) { HaveAPI::Release::Publisher.new(artifacts, tmp) }
    let(:mirror) { File.join(tmp, 'mirror') }
    let(:remote) { File.join(tmp, 'remote.git') }

    before do
      fixture_manifest
      tar(File.join(tmp, "haveapi-client-php-#{artifacts.version}.tar"), {
        'composer.json' => JSON.generate({ name: 'haveapi/client', version: artifacts.version }),
        'src/Client.php' => 'new client'
      })
      # The fixture archive changes after construction; hash validation is covered separately.
      allow(artifacts).to receive(:verify).and_return({ 'files' => {} })
      described_class.run('git', 'init', '--bare', '--initial-branch=master', remote)
      described_class.run('git', 'clone', remote, mirror)
      File.write(File.join(mirror, 'composer.json'), JSON.generate({ name: 'haveapi/client', version: '0.0.1' }))
      File.write(File.join(mirror, 'removed.php'), 'obsolete')
      FileUtils.mkdir_p(File.join(mirror, '.github'))
      File.write(File.join(mirror, '.github/policy'), 'preserve')
      git(mirror, 'add', '--', 'composer.json', 'removed.php', '.github/policy')
      commit(mirror, 'Initial published PHP version')
      git(mirror, 'tag', 'v0.0.1')
      git(mirror, 'push', '--atomic', 'origin', 'master', 'refs/tags/v0.0.1')
    end

    it 'pushes a clean snapshot and tag, preserves mirror metadata and resumes without changes' do
      publisher.sync_php(mirror)
      first_head = git(mirror, 'rev-parse', 'HEAD')
      expect(File.read(File.join(mirror, 'src/Client.php'))).to eq('new client')
      expect(File.exist?(File.join(mirror, 'removed.php'))).to be(false)
      expect(File.read(File.join(mirror, '.github/policy'))).to eq('preserve')
      expect(git(remote, 'rev-parse', 'master')).to eq(first_head)
      publisher.sync_php(mirror)
      expect(git(mirror, 'rev-parse', 'HEAD')).to eq(first_head)
    end

    it 'refuses untagged mirror changes before altering files' do
      File.write(File.join(mirror, 'removed.php'), 'unreleased change')
      git(mirror, 'add', '--', 'removed.php')
      commit(mirror, 'Unreleased mirror change')
      expect { publisher.sync_php(mirror) }.to raise_error(HaveAPI::Release::Error, /untagged changes/)
      expect(File.read(File.join(mirror, 'removed.php'))).to eq('unreleased change')
    end

    it 'refuses a PHP conflict before any registry publication' do
      git(mirror, 'tag', artifacts.tag)
      allow(publisher).to receive(:with_php_mirror).and_yield(mirror, {})
      allow(publisher).to receive(:publish_registries)
      allow(publisher).to receive(:finish_github)
      expect { publisher.publish }.to raise_error(HaveAPI::Release::Error, /different content or source/)
      expect(publisher).not_to have_received(:publish_registries)
      expect(publisher).not_to have_received(:finish_github)
    end

    it 'refuses an existing version tag with different content or provenance' do
      git(mirror, 'tag', artifacts.tag)
      expect { publisher.sync_php(mirror) }.to raise_error(HaveAPI::Release::Error, /different content or source/)
    end
  end
end
