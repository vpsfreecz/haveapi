require 'rspec'
require_relative '../publish'

RSpec.describe HaveAPI::Release::Publisher do
  let(:state) { { directory: Dir.mktmpdir('haveapi-publisher-spec-'), now: [0.0], reads: [], registry: {} } }
  let(:manifest) do
    names = gem_names.map { |name| "#{name}-#{version}.gem" } + python_names + [npm_name]
    files = names.to_h do |name|
      File.binwrite(File.join(directory, name), "retained #{name}\n")
      [name, Digest::SHA256.file(File.join(directory, name)).hexdigest]
    end
    { 'files' => files, 'run_id' => '123' }
  end
  let(:artifacts) do
    instance_double(HaveAPI::Release::Artifacts, version:, tag: "v#{version}", python_names:, verify: manifest)
  end
  let(:registry_query) do
    HaveAPI::Release::RegistryQuery.new(
      clock: -> { now[0] }, sleeper: ->(seconds) { now[0] += seconds }, logger: ->(_line) {},
      transport: lambda do |uri, _remaining|
        canonical = uri.dup
        canonical.query = nil
        reads << [canonical.to_s, uri.query]
        metadata = registry[canonical.to_s]
        metadata = metadata.call(uri) if metadata.respond_to?(:call)
        [metadata ? 200 : 404, JSON.generate(metadata), {}]
      end
    )
  end
  let(:publisher) { described_class.new(artifacts, directory, registry: registry_query) }

  %i[directory now reads registry].each do |name|
    define_method(name) { state.fetch(name) }
  end

  before do
    allow(publisher).to receive(:warn)
    allow(HaveAPI::Release).to receive(:capture).with('npm', '--version').and_return('11.5.1')
    allow(HaveAPI::Release).to receive(:run) do |*command|
      raise "Unexpected publication command: #{command.inspect}"
    end
  end

  after { FileUtils.remove_entry(directory) }

  def version
    '0.30.0'
  end

  def gem_names
    HaveAPI::Release::GEMS.keys
  end

  def python_names
    ["haveapi_client-#{version}-py3-none-any.whl", "haveapi_client-#{version}.tar.gz"]
  end

  def npm_name
    "haveapi-client-#{version}.tgz"
  end

  def gem_url(name)
    "https://rubygems.org/api/v2/rubygems/#{name}/versions/#{version}.json"
  end

  def matching_gem(name)
    { 'name' => name, 'version' => version, 'platform' => 'ruby', 'sha' => manifest.fetch('files').fetch("#{name}-#{version}.gem") }
  end

  def npm_url
    "https://registry.npmjs.org/haveapi-client/#{version}"
  end

  def matching_npm
    {
      'name' => 'haveapi-client', 'version' => version,
      'dist' => { 'integrity' => "sha512-#{Digest::SHA512.file(File.join(directory, npm_name)).base64digest}" }
    }
  end

  def matching_python(names = python_names)
    { 'info' => { 'name' => 'haveapi-client', 'version' => version },
      'urls' => names.map { |name| { 'filename' => name, 'digests' => { 'sha256' => manifest.fetch('files').fetch(name) } } } }
  end

  def pypi_url
    "https://pypi.org/pypi/haveapi-client/#{version}/json"
  end

  def prepare_python
    allow(publisher).to receive(:with_php_mirror).and_yield('isolated-mirror', {})
    allow(publisher).to receive(:preflight_php)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('GITHUB_OUTPUT').and_return(File.join(directory, 'output'))
    publisher.prepare_pypi
  end

  def capture_gem_pushes
    commands = []
    allow(HaveAPI::Release).to receive(:run) do |*command|
      (gem_names.map { |name| gem_url(name) } + [npm_url]).each do |url|
        expect(reads.map(&:first)).to include(url)
      end
      expect(command.first(2)).to eq(%w[gem push])
      name = File.basename(command.fetch(2)).delete_suffix("-#{version}.gem")
      expect(command).to eq(['gem', 'push', File.join(directory, "#{name}-#{version}.gem"), '--host', 'https://rubygems.org'])
      commands << name
      registry[gem_url(name)] = matching_gem(name)
    end
    commands
  end

  it 'preflights all five gems, including TypeScript, before staging the first Python upload' do
    prepare_python

    expect(gem_names.length).to eq(5)
    expect(gem_names).to include('haveapi-rust-client', 'haveapi-typescript-client')
    expect(reads.map(&:first).uniq.first(5)).to eq(gem_names.map { |name| gem_url(name) })
    expect(Dir.children(File.join(directory, 'python-publish')).sort).to eq(python_names.sort)
    expect(HaveAPI::Release).not_to have_received(:run)
  end

  it 'refuses a conflicting Rust gem before staging Python or writing any registry' do
    registry[gem_url('haveapi-rust-client')] = { 'sha' => 'different' }

    expect { prepare_python }.to raise_error(HaveAPI::Release::Error, /Existing RubyGems version differs: haveapi-rust-client/)
    expect(File).not_to exist(File.join(directory, 'python-publish'))
    expect(HaveAPI::Release).not_to have_received(:run)
  end

  it 'checks a conflicting Rust gem before pushing earlier missing gems' do
    registry[gem_url('haveapi-rust-client')] = { 'sha' => 'different' }

    expect { publisher.publish_registries }.to raise_error(HaveAPI::Release::Error, /Existing RubyGems version differs: haveapi-rust-client/)
    expect(HaveAPI::Release).not_to have_received(:run)
  end

  it 'refuses a conflicting TypeScript gem before staging Python or uploading earlier gems' do
    registry[gem_url('haveapi-typescript-client')] = { 'sha' => 'different' }
    expect { prepare_python }.to raise_error(HaveAPI::Release::Error, /Existing RubyGems version differs: haveapi-typescript-client/)
    expect { publisher.publish_registries }.to raise_error(HaveAPI::Release::Error, /Existing RubyGems version differs: haveapi-typescript-client/)
    expect(File).not_to exist(File.join(directory, 'python-publish'))
    expect(HaveAPI::Release).not_to have_received(:run)
  end

  it 'skips matching gems and uploads only the missing TypeScript gem once' do
    publisher
    (gem_names - ['haveapi-typescript-client']).each { |name| registry[gem_url(name)] = matching_gem(name) }
    registry[npm_url] = matching_npm
    commands = capture_gem_pushes
    publisher.publish_registries
    expect(commands).to eq(['haveapi-typescript-client'])
    commands.clear
    publisher.publish_registries
    expect(commands).to be_empty
  end

  it 'keeps the GitHub release private while the TypeScript gem is unconfirmed' do
    gem_names.each { |name| registry[gem_url(name)] = matching_gem(name) }
    registry.delete(gem_url('haveapi-typescript-client'))
    allow(publisher).to receive(:github_release).and_return({ 'draft' => true })
    expect { publisher.finish_github }.to raise_error(HaveAPI::Release::Error, /Registry final validation timed out/)
    expect(HaveAPI::Release).not_to have_received(:run)
    expect(publisher).not_to have_received(:github_release)
  end

  it 'publishes every missing gem client-first after complete registry preflight' do
    publisher
    registry[npm_url] = matching_npm
    commands = capture_gem_pushes

    publisher.publish_registries

    expect(commands).to eq(gem_names)
    expect(commands.first).to eq('haveapi-client')
    expect(commands).to include('haveapi-rust-client')
  end

  it 'skips matching retained gems and uploads only the missing Rust gem' do
    publisher
    (gem_names - ['haveapi-rust-client']).each { |name| registry[gem_url(name)] = matching_gem(name) }
    registry[npm_url] = matching_npm
    commands = capture_gem_pushes

    publisher.publish_registries
    expect(commands).to eq(['haveapi-rust-client'])

    commands.clear
    publisher.publish_registries
    expect(commands).to be_empty
  end

  it 'keeps the GitHub release private while the Rust gem is unconfirmed' do
    gem_names.each { |name| registry[gem_url(name)] = matching_gem(name) }
    registry.delete(gem_url('haveapi-rust-client'))
    allow(publisher).to receive(:github_release).and_return({ 'draft' => true })

    expect { publisher.finish_github }.to raise_error(HaveAPI::Release::Error, /Registry final validation timed out/)
    expect(HaveAPI::Release).not_to have_received(:run)
    expect(publisher).not_to have_received(:github_release)
  end

  it 'makes the GitHub release public only after every destination is confirmed' do
    publisher
    gem_names.each { |name| registry[gem_url(name)] = matching_gem(name) }
    registry[npm_url] = matching_npm
    allow(publisher).to receive_messages(pypi_files: python_names.to_h { |name| [name, true] }, github_release: { 'draft' => true })
    allow(HaveAPI::Release).to receive(:run).with('gh', 'release', 'edit', "v#{version}", '--repo', 'vpsfreecz/haveapi', '--draft=false')

    publisher.finish_github

    expect(reads.map(&:first)).to include(gem_url('haveapi-rust-client'))
    expect(HaveAPI::Release).to have_received(:run).with('gh', 'release', 'edit', "v#{version}", '--repo', 'vpsfreecz/haveapi', '--draft=false')
  end

  %w[name version platform sha].each do |field|
    [nil, 'different', :absent].each do |bad|
      it "rejects #{field}=#{bad.inspect} before alternate reads or publication" do
        name = gem_names.last
        registry[gem_url(name)] = bad == :absent ? matching_gem(name).except(field) : matching_gem(name).merge(field => bad)
        expect { publisher.gem_present?(name, wait: true) }.to raise_error(HaveAPI::Release::Error, /differs/)
        expect(reads).to eq([[gem_url(name), nil]])
        expect(HaveAPI::Release).not_to have_received(:run)
      end
    end
  end

  it 'validates a fresh positive before deciding that an existing gem is missing' do
    name = gem_names.last
    registry[gem_url(name)] = ->(uri) { uri.query ? matching_gem(name) : nil }
    expect(publisher.gem_present?(name)).to be(true)
    expect(reads.size).to eq(2)
    expect(HaveAPI::Release).not_to have_received(:run)
  end

  it 'never repeats an accepted upload or attempts npm while TypeScript remains unconfirmed' do
    publisher
    (gem_names - [gem_names.last]).each { |name| registry[gem_url(name)] = matching_gem(name) }
    pushes = []
    allow(HaveAPI::Release).to receive(:run) { |*command| pushes << command }
    expect { publisher.publish_registries }.to raise_error(HaveAPI::Release::Error, /upload succeeded.*npm, PHP, GitHub/)
    expect(pushes).to eq([['gem', 'push', File.join(directory, "#{gem_names.last}-#{version}.gem"), '--host', 'https://rubygems.org']])
    expect(now[0]).to be <= 600
  end

  it 'retains the exact recovery tag, run URL and manifest path in a confirmation failure' do
    expect { publisher.gem_present?(gem_names.last, wait: true, uploaded: true) }
      .to raise_error(HaveAPI::Release::Error, %r{Tag: v0.30.0; run: https://github.com/vpsfreecz/haveapi/actions/runs/123; manifest: #{Regexp.escape(directory)}/release-manifest.json})
  end

  it 'waits for complete Python metadata before allowing later publication' do
    first = matching_python([python_names.first])
    registry[pypi_url] = ->(_uri) { now[0] < 6 ? first : matching_python }
    allow(publisher).to receive(:with_php_mirror).and_yield('mirror', {})
    allow(publisher).to receive(:preflight_php)
    allow(publisher).to receive(:publish_registries) { expect(now[0]).to eq(6) }
    allow(publisher).to receive(:sync_php)
    allow(publisher).to receive(:finish_github)
    publisher.publish
    expect(publisher).to have_received(:publish_registries).once
    expect(publisher).to have_received(:sync_php).once
    expect(publisher).to have_received(:finish_github).once
    expect(HaveAPI::Release).not_to have_received(:run)
  end

  it 'uses one absolute deadline across final destination validation' do
    gem_names.each_with_index do |name, index|
      registry[gem_url(name)] = lambda do |_uri|
        now[0] += 200 if index < 3
        matching_gem(name)
      end
    end
    expect { publisher.finish_github }.to raise_error(HaveAPI::Release::Error, /final validation timed out/)
    expect(now[0]).to eq(600)
    expect(reads.map(&:first)).not_to include(gem_url(gem_names.last), npm_url, pypi_url)
    expect(HaveAPI::Release).not_to have_received(:run)
  end

  it 'stages only missing original Python bytes after validating partial metadata' do
    registry[pypi_url] = matching_python([python_names.first])
    prepare_python
    stage = File.join(directory, 'python-publish')
    expect(Dir.children(stage)).to eq([python_names.last])
    expect(File.binread(File.join(stage, python_names.last))).to eq(File.binread(File.join(directory, python_names.last)))
  end

  it 'does not stage anything when Python identity or filenames conflict' do
    registry[pypi_url] = matching_python.merge('info' => { 'name' => 'other', 'version' => version })
    expect { prepare_python }.to raise_error(HaveAPI::Release::Error, /identity differs/)
    expect(File).not_to exist(File.join(directory, 'python-publish'))
    expect(HaveAPI::Release).not_to have_received(:run)
  end

  %i[version digest missing_digest duplicate unexpected malformed_files].each do |problem|
    it "rejects Python #{problem} before staging or alternate reads" do
      metadata = matching_python
      case problem
      when :version then metadata['info']['version'] = '0.30.1'
      when :digest then metadata['urls'].first['digests']['sha256'] = 'different'
      when :missing_digest then metadata['urls'].first['digests'].delete('sha256')
      when :duplicate then metadata['urls'] << metadata['urls'].first
      when :unexpected then metadata['urls'].first['filename'] = 'unexpected.whl'
      when :malformed_files then metadata['urls'] = {}
      end
      registry[pypi_url] = metadata
      expect { prepare_python }.to raise_error(HaveAPI::Release::Error)
      expect(reads.count { |endpoint, _query| endpoint == pypi_url }).to eq(1)
      expect(File).not_to exist(File.join(directory, 'python-publish'))
      expect(HaveAPI::Release).not_to have_received(:run)
    end
  end

  it 'retains a matching canonical file for staging when the fresh response is missing' do
    registry[pypi_url] = ->(uri) { uri.query ? nil : matching_python([python_names.first]) }
    prepare_python
    expect(Dir.children(File.join(directory, 'python-publish'))).to eq([python_names.last])
    expect(publisher).to have_received(:warn).with(/metadata visibility regressed; retaining validated file presence for staging only/)
  end

  it 'uses disjoint validated partial views only to skip uploads, not to confirm completion' do
    registry[pypi_url] = lambda do |uri|
      matching_python([uri.query ? python_names.last : python_names.first])
    end
    prepare_python
    expect(File).not_to exist(File.join(directory, 'python-publish'))
    expect(File.read(File.join(directory, 'output'))).to eq("publish=false\n")
    expect { publisher.pypi_files(wait: true, deadline: registry_query.deadline(10)) }
      .to raise_error(HaveAPI::Release::Error, /public metadata remains unconfirmed/)
    expect(HaveAPI::Release).not_to have_received(:run)
  end

  it 'retains known files across a temporary read error and a later regressing view' do
    sequence = [matching_python([python_names.first]), Net::ReadTimeout.new, nil, nil]
    registry[pypi_url] = lambda do |_uri|
      value = sequence.shift
      raise value if value.is_a?(Exception)

      value
    end
    prepare_python
    expect(Dir.children(File.join(directory, 'python-publish'))).to eq([python_names.last])
    expect(now[0]).to eq(2)
  end

  it 'does not carry observed presence into another invocation' do
    registry[pypi_url] = ->(uri) { uri.query ? nil : matching_python([python_names.first]) }
    expect(publisher.pypi_files.keys).to eq([python_names.first])
    registry[pypi_url] = nil
    expect(publisher.pypi_files).to eq({})
  end

  it 'fails on a later conflicting hash even after observing a correct file' do
    bad = matching_python([python_names.last])
    bad['urls'].first['digests']['sha256'] = 'different'
    registry[pypi_url] = ->(uri) { uri.query ? bad : matching_python([python_names.first]) }
    expect { prepare_python }.to raise_error(HaveAPI::Release::Error, /PyPI file differs/)
    expect(File).not_to exist(File.join(directory, 'python-publish'))
    expect(HaveAPI::Release).not_to have_received(:run)
  end

  %i[duplicate unexpected schema].each do |problem|
    it "rejects later Python #{problem} despite earlier matching evidence" do
      bad = matching_python([python_names.last])
      case problem
      when :duplicate then bad['urls'] << bad['urls'].first
      when :unexpected then bad['urls'].first['filename'] = 'unexpected.whl'
      when :schema then bad['urls'] = nil
      end
      registry[pypi_url] = ->(uri) { uri.query ? bad : matching_python([python_names.first]) }
      expect { prepare_python }.to raise_error(HaveAPI::Release::Error)
      expect(File).not_to exist(File.join(directory, 'python-publish'))
      expect(HaveAPI::Release).not_to have_received(:run)
    end
  end

  it 'does not treat a withdrawn file as permission to upload during confirmation' do
    registry[pypi_url] = matching_python([python_names.first])
    allow(publisher).to receive(:with_php_mirror).and_yield('mirror', {})
    allow(publisher).to receive(:preflight_php)
    allow(publisher).to receive(:publish_registries)
    expect { publisher.publish }.to raise_error(HaveAPI::Release::Error, /Python completeness timed out/)
    expect(publisher).not_to have_received(:publish_registries)
    expect(HaveAPI::Release).not_to have_received(:run)
  end
end
