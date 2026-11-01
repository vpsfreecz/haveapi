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
  let(:shallow_files) { "  s.files       = `git ls-files -z`.split(\"\\x0\") + Dir.glob('doc/*')\n" }
  let(:recursive_files) { "  s.files       = `git ls-files -z`.split(\"\\x0\") + Dir.glob('doc/**/*').select { |path| File.file?(path) }\n" }

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

  def with_files(contents, statement)
    path = 'servers/ruby/haveapi.gemspec'
    previous = contents.fetch(path).lines.find { |line| line.start_with?('  s.files ') }
    contents.merge(path => contents.fetch(path).sub(previous, statement))
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

  def replay_samples(baseline = '0.31.0', selections: {}, normalize_files: true)
    samples, budgets = PerformanceSamples.fixture
    samples.fetch('sources').each do |role, source|
      contents = source_contents(role == 'baseline' ? baseline : '0.31.1').slice(*HaveAPI::Performance::SourceVersions::PATHS)
      contents = with_files(contents, selections.fetch(role)) if selections.has_key?(role)
      receipt = HaveAPI::Performance::SourceVersions.capture(contents, normalize_files:)
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

  it 'accepts only the reviewed packaging transition in preparation and live input capture' do
    contents = { baseline: with_files(source_contents('0.31.1'), shallow_files),
                 candidate: with_files(source_contents('0.31.1'), recursive_files) }
    prepare(contents[:baseline], contents[:candidate]) do |roots|
      retained = JSON.parse(File.read(File.join(File.dirname(roots[:baseline]), 'dependency-compatibility.json')))
      expect(retained['baseline']['gemspecs']).to eq(retained['candidate']['gemspecs'])
      receipts = retained.values.map { |input| input.fetch('source_versions') }
      expect(receipts.first.fetch('raw_sha256')).not_to eq(receipts.last.fetch('raw_sha256'))
      expect(receipts.first.fetch('normalized_sha256')).to eq(receipts.last.fetch('normalized_sha256'))
      expect(receipts.map { |receipt| receipt.fetch('file_selection') }).to eq(%w[documentation-files-v1 documentation-files-v1])

      graphs = roots.map do |role, directory|
        %w[HaveAPI::VERSION HaveAPI::Client::VERSION HaveAPI::RustClient::VERSION].each { |constant| stub_const(constant, '0.31.1') }
        inputs = JSON.parse(JSON.generate(HaveAPI::Performance::Worker.inputs(directory, 'quick', benchmark: true)))
        hashes = contents.fetch(role).transform_values { |text| Digest::SHA256.hexdigest(text) }
        expect(inputs.fetch('source_versions')).to eq(retained.fetch(role.to_s).fetch('source_versions'))
        expect do
          HaveAPI::Performance.validate_input_receipts(inputs, { 'files_sha256' => hashes }, profile: 'quick', lineage: nil)
        end.not_to raise_error
        HaveAPI::Performance::Release.graph(inputs)
      end
      expect(graphs.first).to eq(graphs.last)
    end
  end

  it 'replays the exact old/new packaging pair while retaining raw source hashes' do
    samples, budgets = replay_samples('0.31.1', selections: { 'baseline' => shallow_files, 'candidate' => recursive_files })

    expect(compare(samples, budgets).fetch('status')).to eq('pass')
    path = 'servers/ruby/haveapi.gemspec'
    expect(samples['sources']['baseline']['files_sha256'][path]).not_to eq(samples['sources']['candidate']['files_sha256'][path])
  end

  it 'keeps all bytes outside the exact packaging statement and evaluated requirements strict' do
    original = with_files(source_contents('0.31.0'), shallow_files)
    candidate = with_files(source_contents('0.31.1'), recursive_files)
    path = 'servers/ruby/haveapi.gemspec'
    changes = [
      candidate.merge(path => candidate.fetch(path).sub('Framework for creating', 'Framework for describing')),
      candidate.merge(path => candidate.fetch(path).sub("'activesupport', '>= 7.1'", "'activesupport', '>= 7.0'")),
      candidate.merge(path => "#{candidate.fetch(path)}\n# unrelated comment\n"),
      candidate.merge('.ruby-version' => "3.2.1\n")
    ]
    changes.each do |changed|
      expect { prepare(original, changed) }.to raise_error(HaveAPI::PerformanceCI::Error, /Dependency inputs differ/)
    end
  end

  it 'does not normalize unknown, absent, duplicated or modified file statements' do
    contents = source_contents('0.31.1').slice(*HaveAPI::Performance::SourceVersions::PATHS)
    expected = HaveAPI::Performance::SourceVersions.capture(with_files(contents, shallow_files)).fetch('normalized_sha256')
    variants = [
      recursive_files.sub('doc/**/*', 'doc/**'), recursive_files.sub('File.file?', 'File.symlink?'),
      recursive_files.sub("\n", " # additional behavior\n"), '', shallow_files + recursive_files,
      "#{recursive_files}  s.files = []\n"
    ]
    variants.each do |statement|
      changed = with_files(contents, statement)
      receipt = HaveAPI::Performance::SourceVersions.capture(changed)
      expect(receipt).not_to have_key('file_selection')
      expect(receipt.fetch('normalized_sha256')).not_to eq(expected)
      expect(receipt).to eq(HaveAPI::Performance::SourceVersions.capture(changed, normalize_files: false))
    end
  end

  it 'rejects tampered or stripped packaging markers and source bindings on replay' do
    %w[marker stripped added raw normalized content source manifest].each do |fault|
      selections = fault == 'added' ? {} : { 'baseline' => shallow_files, 'candidate' => recursive_files }
      samples, budgets = replay_samples(selections:, normalize_files: fault != 'added')
      inputs = samples['observations']['candidate']['inputs']
      receipt = inputs.fetch('source_versions')
      path = 'servers/ruby/haveapi.gemspec'
      case fault
      when 'marker' then receipt['file_selection'] = 'unreviewed-policy'
      when 'stripped' then receipt.delete('file_selection')
      when 'added' then receipt['file_selection'] = 'documentation-files-v1'
      when 'raw' then receipt['raw_sha256'][path] = 'f' * 64
      when 'normalized' then receipt['normalized_sha256'][path] = 'f' * 64
      when 'content' then receipt['contents'][path] += "# changed\n"
      when 'source' then samples['sources']['candidate']['files_sha256'][path] = 'f' * 64
      when 'manifest' then inputs['manifests'][path] = 'f' * 64
      end
      expect { compare(samples, budgets) }.to raise_error(error), fault
    end
  end

  it 'continues to replay legacy own-version receipts with raw file selection' do
    samples, budgets = replay_samples(normalize_files: false)

    expect(compare(samples, budgets).fetch('status')).to eq('pass')
  end

  it 'leaves the historical maintenance packaging comparison strict' do
    contents = source_contents('0.30.1')
    old = HaveAPI::Performance::Release.capture(with_files(contents, shallow_files))
    new = HaveAPI::Performance::Release.capture(with_files(contents, recursive_files))

    expect(old.fetch('normalized_sha256')).not_to eq(new.fetch('normalized_sha256'))
  end
end
