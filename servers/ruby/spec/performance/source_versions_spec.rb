require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../../../utils/performance_ci'
require_relative '../../benchmarks/endpoints'
require_relative '../../../../clients/ruby/lib/haveapi/client/version'
require_relative '../../../../clients/rust/lib/haveapi/rust_client/version'
require_relative 'support/samples'

describe HaveAPI::PerformanceCI::Campaign do
  let(:root) { File.expand_path('../../../..', __dir__) }
  let(:error) { HaveAPI::Performance::ContractError }

  before do
    # These metadata fixtures evaluate real gemspecs without loading the optional
    # Rust adapter. Ordinary server bundles do not include its dependencies; the
    # real benchmark environment checks their installed identities separately.
    allow(Gem::Specification).to receive(:find_by_name).and_call_original
    { 'fiddle' => '1.1.8', 'tomlrb' => '2.0.5' }.each do |name, version|
      specification = Gem::Specification.new do |spec|
        spec.name = name
        spec.version = version
      end
      allow(Gem::Specification).to receive(:find_by_name).with(name).and_return(specification)
    end
  end

  def source_contents(version)
    paths = HaveAPI::Performance::Release.paths('quick')
    actual = File.read(File.join(root, 'VERSION')).strip
    paths.to_h do |path|
      text = File.read(File.join(root, path))
      text = "#{version}\n" if path == 'VERSION'
      text = text.sub("VERSION = '#{actual}'", "VERSION = '#{version}'") if HaveAPI::Performance::Release::VERSIONS.has_key?(path)
      text = text.sub("'haveapi-client', '~> #{actual}'", "'haveapi-client', '~> #{version}'") if path.end_with?('.gemspec')
      [path, text]
    end
  end

  def write_source(directory, contents)
    contents.each do |path, text|
      FileUtils.mkdir_p(File.dirname(File.join(directory, path)))
      File.write(File.join(directory, path), text)
    end
  end

  def prepare(baseline, candidate)
    Dir.mktmpdir('haveapi-own-versions-') do |directory|
      roots = { baseline: File.join(directory, 'baseline'), candidate: File.join(directory, 'candidate') }
      write_source(roots[:baseline], baseline)
      write_source(roots[:candidate], candidate)
      campaign = described_class.new(repository: nil, selection: { 'profile' => 'quick' }, evidence: directory, sources: directory)
      campaign.send(:verify_dependencies, roots)
      yield roots if block_given?
    end
  end

  %w[0.30.0 0.31.0].each do |baseline|
    it "accepts synchronized #{baseline} to 0.31.1 metadata during preparation" do
      expect { prepare(source_contents(baseline), source_contents('0.31.1')) }.not_to raise_error
    end

    it "retains and validates the live worker graph for #{baseline} to 0.31.1" do
      prepare(source_contents(baseline), source_contents('0.31.1')) do |roots|
        graphs = roots.map do |role, directory|
          version = role == :baseline ? baseline : '0.31.1'
          %w[HaveAPI::VERSION HaveAPI::Client::VERSION HaveAPI::RustClient::VERSION].each { |constant| stub_const(constant, version) }
          inputs = JSON.parse(JSON.generate(HaveAPI::Performance::Worker.inputs(directory, 'quick', benchmark: true)))
          hashes = source_contents(version).transform_values { |text| Digest::SHA256.hexdigest(text) }
          expect do
            HaveAPI::Performance.validate_input_receipts(inputs, { 'files_sha256' => hashes }, profile: 'quick', lineage: nil)
          end.not_to raise_error
          HaveAPI::Performance::Release.graph(inputs)
        end
        expect(graphs.first).to eq(graphs.last)
      end
    end

    it "replays the synchronized #{baseline} to 0.31.1 graph" do
      samples, budgets = replay_samples(baseline)
      expect(compare(samples, budgets).fetch('status')).to eq('pass')
    end
  end

  def replay_samples(baseline = '0.31.0')
    samples, budgets = PerformanceSamples.fixture
    samples.fetch('sources').each do |role, source|
      contents = source_contents(role == 'baseline' ? baseline : '0.31.1').slice(*HaveAPI::Performance::SourceVersions::PATHS)
      receipt = HaveAPI::Performance::SourceVersions.capture(contents)
      source['files_sha256'].merge!(receipt.fetch('raw_sha256'))
      samples.fetch('observations').each_value do |observation|
        next unless observation.fetch('source').fetch('root') == source.fetch('root')

        inputs = Marshal.load(Marshal.dump(observation.fetch('inputs')))
        inputs['manifests'].merge!(receipt.fetch('normalized_sha256'))
        inputs['source_versions'] = receipt
        observation['inputs'] = inputs
        samples['inputs'] = HaveAPI::Performance::Release.graph(inputs)
      end
    end
    [samples, JSON.parse(budgets)]
  end

  def compare(samples, budgets)
    HaveAPI::Performance::Comparator.new(samples, budgets, budget_sha256: samples.fetch('budget_sha256')).compare
  end

  it 'rejects external dependency and other unnormalized input edits in preparation' do
    %w[Gemfile .ruby-version servers/ruby/haveapi.gemspec].each do |path|
      changed = source_contents('0.31.1')
      changed[path] = path == '.ruby-version' ? "3.0.0\n" : "#{changed[path]}\n# unrelated change\n"
      expect { prepare(source_contents('0.31.0'), changed) }.to raise_error(HaveAPI::PerformanceCI::Error, /Dependency inputs differ/)
    end
    changed = source_contents('0.31.1')
    changed['servers/ruby/haveapi.gemspec'] = changed['servers/ruby/haveapi.gemspec'].sub("'activesupport', '>= 7.1'", "'activesupport', '>= 999.0'")
    expect { prepare(source_contents('0.31.0'), changed) }.to raise_error(error, /Benchmark dependencies do not satisfy/)
  end

  it 'rejects malformed, missing, duplicate and unsynchronized own declarations' do
    original = source_contents('0.31.1').slice(*HaveAPI::Performance::SourceVersions::PATHS)
    changes = [
      ['VERSION', "0.31.01\n"], ['VERSION', " 0.31.1\n"],
      ['servers/ruby/lib/haveapi/version.rb', original['servers/ruby/lib/haveapi/version.rb'].sub('0.31.1', '0.31.0')],
      ['servers/ruby/lib/haveapi/version.rb', "VERSION = '0.31.1'.freeze\nVERSION = '0.31.1'.freeze\n"],
      ['servers/ruby/haveapi.gemspec', original['servers/ruby/haveapi.gemspec'].sub('~> 0.31.1', '~> 0.31.0')],
      ['servers/ruby/haveapi.gemspec', original['servers/ruby/haveapi.gemspec'].sub("~> 0.31.1'", "~> 0.31.1', '< 0.32'")],
      ['servers/ruby/haveapi.gemspec', "#{original['servers/ruby/haveapi.gemspec']}s.add_dependency 'haveapi-client', '~> 0.31.1'\n"],
      ['servers/ruby/haveapi.gemspec', original['servers/ruby/haveapi.gemspec'].sub('HaveAPI::VERSION', "'0.31.0'")],
      ['clients/ruby/haveapi-client.gemspec', original['clients/ruby/haveapi-client.gemspec'].sub("'haveapi-client'", "'other-client'")]
    ]
    changes.each do |path, text|
      expect { HaveAPI::Performance::SourceVersions.capture(original.merge(path => text)) }.to raise_error(error)
    end
    expect { HaveAPI::Performance::SourceVersions.capture(original.except('VERSION')) }.to raise_error(error)
  end

  it 'rejects loaded versions that do not match the captured source metadata' do
    Dir.mktmpdir('haveapi-own-worker-') do |directory|
      write_source(directory, source_contents('0.31.99'))
      expect { HaveAPI::Performance::Worker.inputs(directory, 'quick', benchmark: true) }.to raise_error(error, /Wrong loaded local package version/)
    end
  end

  it 'rejects tampered, stripped, conflicting or unbound receipts and changed runtime/lock inputs on replay' do
    %w[raw normalized content stripped conflicting source runtime lock].each do |fault|
      samples, budgets = replay_samples
      observation = samples.fetch('observations').fetch('candidate')
      inputs = observation.fetch('inputs')
      receipt = inputs.fetch('source_versions')
      case fault
      when 'raw' then receipt['raw_sha256']['VERSION'] = 'f' * 64
      when 'normalized' then receipt['normalized_sha256']['VERSION'] = 'f' * 64
      when 'content' then receipt['contents']['VERSION'] = "0.31.2\n"
      when 'stripped' then inputs.delete('source_versions')
      when 'conflicting' then inputs['release_versions'] = {}
      when 'source' then samples['sources']['candidate']['files_sha256']['VERSION'] = 'f' * 64
      when 'runtime' then observation['environment'] = { 'ruby' => 'changed' }
      when 'lock' then inputs['locks']['Gemfile.lock'] = 'f' * 64
      end
      expect { compare(samples, budgets) }.to raise_error(error), fault
    end
  end

  it 'continues to replay legacy raw manifests without own-version receipts' do
    samples, budgets = PerformanceSamples.fixture
    expect(compare(samples, JSON.parse(budgets)).fetch('status')).to eq('pass')
  end
end
