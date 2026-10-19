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
    let(:draft) { { 'tag_name' => artifacts.tag, 'draft' => true, 'assets' => [] } }
    let(:list_command) { ['gh', 'api', '--paginate', '--slurp', 'repos/vpsfreecz/haveapi/releases?per_page=100'] }

    def github_response(pages, error: '')
      [JSON.generate(pages), error, instance_double(Process::Status, success?: error.empty?)]
    end

    before do
      fixture_manifest
      allow(described_class).to receive(:run)
      # The tag endpoint does not expose drafts, even after creating one.
      allow(Open3).to receive(:capture3).with('gh', 'api', "repos/vpsfreecz/haveapi/releases/tags/#{artifacts.tag}").and_return(github_response([], error: 'gh: Not Found (HTTP 404)'))
      pages = [[{ 'tag_name' => 'v0.0.1', 'draft' => false, 'assets' => [] }], [draft]]
      allow(Open3).to receive(:capture3).with(*list_command).and_return(github_response(pages))
    end

    it 'finds an existing draft on a later page and uploads its retained artifacts' do
      publisher.prepare_github
      expect(described_class).not_to have_received(:run).with('gh', 'release', 'create', any_args)
      (artifacts.names + ['release-manifest.json']).each do |name|
        expect(described_class).to have_received(:run).with('gh', 'release', 'upload', artifacts.tag, File.join(tmp, name), '--repo', 'vpsfreecz/haveapi')
      end
    end

    it 'finds a newly created draft before uploading artifacts' do
      allow(Open3).to receive(:capture3).with(*list_command).and_return(github_response([[]]), github_response([[draft]]))
      expect { publisher.prepare_github }.not_to raise_error
      expect(described_class).to have_received(:run).with('gh', 'release', 'create', artifacts.tag, '--repo', 'vpsfreecz/haveapi', '--verify-tag', '--draft', '--title', "HaveAPI #{artifacts.version}", '--notes-file', File.join(tmp, 'release-notes.md'))
      expect(described_class).to have_received(:run).with('gh', 'release', 'upload', artifacts.tag, File.join(tmp, 'release-manifest.json'), '--repo', 'vpsfreecz/haveapi')
    end

    it 'also finds an already published release with the exact tag' do
      published = draft.merge('draft' => false)
      allow(Open3).to receive(:capture3).with(*list_command).and_return(github_response([[published]]))
      expect(publisher.github_release).to eq(published)
    end

    [403, 404].each do |status|
      it "keeps HTTP #{status} query failures visible without creating a draft" do
        allow(Open3).to receive(:capture3).with(*list_command).and_return(github_response([], error: "gh: query failed (HTTP #{status})"))
        expect { publisher.prepare_github }.to raise_error(HaveAPI::Release::Error, /GitHub release query failed.*#{status}/)
        expect(described_class).not_to have_received(:run)
      end
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
