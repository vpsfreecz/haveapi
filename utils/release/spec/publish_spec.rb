require 'rspec'
require_relative '../publish'

RSpec.describe HaveAPI::Release::Publisher do
  let(:directory) { Dir.mktmpdir('haveapi-publisher-spec-') }
  let(:manifest) do
    names = gem_names.map { |name| "#{name}-#{version}.gem" } + python_names + [npm_name]
    files = names.to_h do |name|
      File.binwrite(File.join(directory, name), "retained #{name}\n")
      [name, Digest::SHA256.file(File.join(directory, name)).hexdigest]
    end
    { 'files' => files }
  end
  let(:artifacts) do
    instance_double(HaveAPI::Release::Artifacts, version:, tag: "v#{version}", python_names:, verify: manifest)
  end
  let(:publisher) { described_class.new(artifacts, directory) }
  let(:registry) { {} }

  before do
    allow(publisher).to receive(:registry_json) { |url| registry[url] }
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
    { 'sha' => manifest.fetch('files').fetch("#{name}-#{version}.gem") }
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
        expect(publisher).to have_received(:registry_json).with(url).at_least(:once)
      end
      expect(command.first(2)).to eq(%w[gem push])
      name = File.basename(command.fetch(2)).delete_suffix("-#{version}.gem")
      expect(command).to eq(['gem', 'push', File.join(directory, "#{name}-#{version}.gem"), '--host', 'https://rubygems.org'])
      commands << name
      registry[gem_url(name)] = matching_gem(name)
    end
    commands
  end

  it 'preflights all four gems, including Rust, before staging the first Python upload' do
    prepare_python

    expect(gem_names.length).to eq(4)
    expect(gem_names).to include('haveapi-rust-client')
    gem_names.each { |name| expect(publisher).to have_received(:registry_json).with(gem_url(name)).ordered }
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

  it 'publishes every missing gem client-first after complete registry preflight' do
    publisher
    registry[npm_url] = matching_npm
    commands = capture_gem_pushes

    publisher.publish_registries

    expect(commands).to eq(gem_names)
    expect(commands.first).to eq('haveapi-client')
    expect(commands).to include('haveapi-rust-client')
  end

  it 'skips matching retained gems and retries only the missing Rust gem' do
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

    expect { publisher.finish_github }.to raise_error(HaveAPI::Release::Error, /Registry publication is incomplete/)
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

    expect(publisher).to have_received(:registry_json).with(gem_url('haveapi-rust-client'))
    expect(HaveAPI::Release).to have_received(:run).with('gh', 'release', 'edit', "v#{version}", '--repo', 'vpsfreecz/haveapi', '--draft=false')
  end
end
