require 'spec_helper'
require_relative '../../../../utils/performance_ci'
require_relative '../../benchmarks/endpoints'
require_relative '../../../../clients/ruby/lib/haveapi/client/version'
require_relative 'support/samples'
require_relative '../../test_support/documentation_performance_fixture'

describe HaveAPI::Performance::Release do
  let(:root) { File.expand_path('../../../..', __dir__) }
  let(:repository) { HaveAPI::PerformanceCI::Repository.new(git_fixture_root) }
  let(:head) { git_fixture.fetch(:candidate) }
  let(:proof) { repository.release_lineage(head) }
  let(:error) { HaveAPI::Performance::ContractError }

  # Component CI intentionally has shallow source history and no root bundle.
  # Own the proof graph instead of depending on the checkout's maintenance refs.
  around do |example|
    Dir.mktmpdir('haveapi-release-history-') do |directory|
      example.metadata[:git_fixture_root] = directory
      example.metadata[:git_fixture] = build_history(directory)
      example.run
    end
  end

  before do
    stub_const('HaveAPI::Performance::REFERENCE', git_fixture.fetch(:reference))
    stub_const('HaveAPI::Performance::Release::MAPPED', git_fixture.fetch(:mapped))
    stub_const('HaveAPI::Performance::Release::METADATA', git_fixture.fetch(:metadata))
    stub_const('HaveAPI::Performance::Release::TREES', git_fixture.fetch(:trees))
    stub_const('HaveAPI::Performance::Release::DELTA', git_fixture.fetch(:delta_sha256))
  end

  def git_fixture_root
    RSpec.current_example.metadata.fetch(:git_fixture_root)
  end

  def git_fixture
    RSpec.current_example.metadata.fetch(:git_fixture)
  end

  def fixture_git(directory, *arguments, input: '')
    env = { 'GIT_AUTHOR_NAME' => 'Fixture', 'GIT_AUTHOR_EMAIL' => 'fixture@example.test',
            'GIT_COMMITTER_NAME' => 'Fixture', 'GIT_COMMITTER_EMAIL' => 'fixture@example.test',
            'GIT_AUTHOR_DATE' => '2000-01-01T00:00:00Z', 'GIT_COMMITTER_DATE' => '2000-01-01T00:00:00Z' }
    output, errors, status = Open3.capture3(env, 'git', '-C', directory, *arguments, stdin_data: input)
    raise errors unless status.success?

    output
  end

  def fixture_commit(directory, files, parent: nil)
    entries = files.sort.map do |path, body|
      blob = fixture_git(directory, 'hash-object', '-w', '--stdin', input: body).strip
      "100644 blob #{blob}\t#{path}\n"
    end
    tree = fixture_git(directory, 'mktree', input: entries.join).strip
    fixture_git(directory, 'commit-tree', tree, *[('-p' if parent), parent].compact, input: "fixture\n").strip
  end

  def build_history(directory)
    fixture_git(directory, 'init', '--quiet', '--initial-branch=master')
    original = { 'VERSION' => "0.30.0\n", 'CHANGELOG.md' => "original\n" }
    base = fixture_commit(directory, original)
    reference = fixture_commit(directory, original.merge('engine.rb' => "source\n"), parent: base)
    published = original.merge('VERSION' => "0.30.1\n", 'CHANGELOG.md' => "published 0.30.1\n\noriginal\n")
    metadata = fixture_commit(directory, published, parent: base)
    mapped = fixture_commit(directory, published.merge('engine.rb' => "source\n"), parent: metadata)
    candidate = fixture_commit(directory, published.merge('engine.rb' => "source\n", 'tool.rb' => "candidate\n"), parent: mapped)
    fixture_git(directory, 'update-ref', 'refs/heads/master', reference)
    fixture_git(directory, 'update-ref', 'refs/heads/maintenance', candidate)
    delta = fixture_git(directory, 'diff', '--binary', '--full-index', reference, mapped)
    { reference:, metadata:, mapped:, candidate:,
      trees: [reference, mapped, "#{metadata}^", metadata].map { |sha| fixture_git(directory, 'rev-parse', "#{sha}^{tree}").strip },
      delta_sha256: Digest::SHA256.hexdigest(delta) }
  end

  def contents(version, profile: 'quick')
    original = described_class.paths(profile).to_h { |path| [path, File.read(File.join(root, path))] }
    own = original.fetch('VERSION').strip
    original.to_h do |path, value|
      value = "#{version}\n" if path == 'VERSION'
      value = value.sub("VERSION = '#{own}'", "VERSION = '#{version}'") if described_class::VERSIONS.has_key?(path)
      value = value.sub("'haveapi-client', '~> #{own}'", "'haveapi-client', '~> #{version}'") if path.end_with?('.gemspec')
      [path, value]
    end
  end

  def with_maintenance_source
    Dir.mktmpdir('haveapi-maintenance-source-') do |source|
      contents('0.30.2').each do |path, value|
        FileUtils.mkdir_p(File.dirname(File.join(source, path)))
        File.write(File.join(source, path), value)
      end
      yield source
    end
  end

  it 'verifies the complete published binary delta and all four exact trees in an owned history' do
    expect(proof).to include('reference_sha' => HaveAPI::Performance::REFERENCE, 'mapped_sha' => described_class::MAPPED,
                             'metadata_sha' => described_class::METADATA, 'trees' => described_class::TREES)
    expect(Digest::SHA256.hexdigest(proof.fetch('reference_delta'))).to eq(described_class::DELTA)
    expect(proof.fetch('reference_delta')).to eq(proof.fetch('metadata_delta'))
    expect(repository.ancestor?(HaveAPI::Performance::REFERENCE, head)).to be(false)
    expect(repository.ancestor?(described_class::MAPPED, head)).to be(true)
  end

  it 'keeps the proof canonical with abbreviated IDs and changed Git display defaults' do
    [4, 7, 12].each do |abbreviation|
      fixture_git(git_fixture_root, 'config', 'core.abbrev', abbreviation.to_s)
      fixture_git(git_fixture_root, 'config', 'diff.context', '0')
      fixture_git(git_fixture_root, 'config', 'diff.noprefix', 'true')
      fixture_git(git_fixture_root, 'config', 'diff.suppressBlankEmpty', 'true')
      fixture_git(git_fixture_root, 'config', 'diff.external', 'false')
      expect(repository.release_lineage(head)).to eq(proof)
    end
  end

  it 'accepts ordinary master ancestry in a shallow clone without maintenance objects' do
    Dir.mktmpdir('haveapi-shallow-master-') do |directory|
      fixture_git(directory, 'clone', '--quiet', '--depth=1', '--single-branch', '--branch=master',
                  "file://#{git_fixture_root}", '.')
      shallow = HaveAPI::PerformanceCI::Repository.new(directory)
      expect { shallow.git('cat-file', '-e', described_class::MAPPED) }.to raise_error(HaveAPI::PerformanceCI::Error)
      expect(shallow.release_lineage(HaveAPI::Performance::REFERENCE)).to be_nil
    end
  end

  it 'rejects modified metadata, reference trees and candidate binding during replay' do
    %w[metadata_delta reference_delta trees candidate_sha].each do |field|
      changed = Marshal.load(Marshal.dump(proof))
      changed[field] = field == 'trees' ? ['f' * 40] * 4 : 'wrong'
      expect { described_class.validate_lineage(changed, head) }.to raise_error(error, /lineage/)
    end
  end

  it 'does not infer the mapping for nonancestor candidates and fails on missing history' do
    expect(repository.release_lineage(HaveAPI::Performance::REFERENCE)).to be_nil
    expect { repository.release_lineage('f' * 40) }.to raise_error(HaveAPI::PerformanceCI::Error, /ancestry/)
    git = ->(*) { raise HaveAPI::PerformanceCI::Error, 'missing metadata object' }
    expect do
      described_class.lineage(git:, ancestor: ->(left, _right) { left == described_class::MAPPED }, candidate: head)
    end.to raise_error(HaveAPI::PerformanceCI::Error, /missing metadata/)
  end

  it 'rejects a wrong full tree delta on the live proof path' do
    git = lambda do |*arguments|
      result = repository.git(*arguments)
      arguments.include?('diff') ? "#{result}\n# changed" : result
    end
    expect do
      described_class.lineage(git:, ancestor: repository.method(:ancestor?), candidate: head)
    end.to raise_error(error, /lineage/)
  end

  it 'uses the same proof in the direct runner and limits nonliteral ancestry to weekly' do
    %w[weekly quick missing wrong-delta].each do |mode|
      profile = mode == 'quick' ? 'quick' : 'weekly'
      cli = HaveAPI::Performance::CLI.new(['run', '--baseline-sha', HaveAPI::Performance::REFERENCE,
                                           '--candidate-sha', head, '--profile', profile,
                                           '--baseline-root', root, '--candidate-root', root,
                                           '--budgets', 'unused', '--output', 'unused'])
      cli.send(:parse)
      allow(cli).to receive(:verify_runtime)
      allow(HaveAPI::Performance).to receive(:gemspec)
      allow(cli).to receive(:verify_source) { |role| { root: "/controlled/#{role}", sha: head } }
      allow(cli).to receive(:git) { |*arguments| repository.git(*arguments) }
      allow(cli).to receive(:ancestor?) { |left, right| repository.ancestor?(left, right) }
      if mode == 'missing'
        allow(cli).to receive(:ancestor?).and_return(false)
      elsif mode == 'wrong-delta'
        allow(cli).to receive(:git).with(*described_class::DIFF, HaveAPI::Performance::REFERENCE, described_class::MAPPED).and_return('wrong')
      end
      allow(cli).to receive(:child).and_raise(error, 'unexpected worker')
      if mode == 'weekly'
        allow(cli).to receive(:child).with('baseline', {}, 'pilot').and_raise(error, 'verified pilot boundary')
        expect { cli.send(:run_samples, 'f' * 64) }.to raise_error(error, 'verified pilot boundary')
        expect(cli).to have_received(:child).with('baseline', {}, 'pilot')
      else
        expect { cli.send(:run_samples, 'f' * 64) }.to raise_error(error, /ancestor|lineage/)
        expect(cli).not_to have_received(:child)
      end
    end
  end

  it 'normalizes only synchronized own patch identities, preserving every external input' do
    %w[quick weekly].each do |profile|
      old = described_class.capture(contents('0.30.1', profile:))
      new = described_class.capture(contents('0.30.2', profile:))
      expect(old.fetch('raw_sha256')).not_to eq(new.fetch('raw_sha256'))
      expect(old.fetch('normalized_sha256')).to eq(new.fetch('normalized_sha256'))
      expect(new.fetch('own_version')).to eq('0.30.2')
      %w[flake.lock flake.nix .ruby-version Gemfile].each do |path|
        changed = contents('0.30.2', profile:)
        changed[path] += "\n# arbitrary input change\n"
        expect(described_class.capture(changed).fetch('normalized_sha256')).not_to eq(old.fetch('normalized_sha256'))
      end
      %w[required_ruby_version summary activesupport].each do |field|
        changed = contents('0.30.2', profile:)
        changed['servers/ruby/haveapi.gemspec'] = changed.fetch('servers/ruby/haveapi.gemspec').sub(field, "changed_#{field}")
        expect(described_class.capture(changed).fetch('normalized_sha256')).not_to eq(old.fetch('normalized_sha256'))
      end
    end
  end

  it 'builds maintenance fixtures from a later minor source template without broadening the release guard' do
    Dir.mktmpdir('haveapi-later-minor-template-') do |template|
      contents('0.32.0').each do |path, value|
        FileUtils.mkdir_p(File.dirname(File.join(template, path)))
        File.write(File.join(template, path), value)
      end
      allow(self).to receive(:root).and_return(template)
      expect(described_class.capture(contents('0.30.2')).fetch('own_version')).to eq('0.30.2')
      expect { described_class.capture(contents('0.32.0')) }.to raise_error(error, /Expected own 0\.30 patch version/)
    end
  end

  it 'rejects mismatched own constants, package names, constraints and minor versions' do
    expect { described_class.capture(contents('0.31.0')) }.to raise_error(error, /Expected own 0\.30 patch version/)
    [
      ['VERSION', "0.31.2\n"],
      ['VERSION', " 0.30.2\n"],
      ['servers/ruby/lib/haveapi/version.rb', "module HaveAPI\n VERSION = '0.30.3'\nend\n"],
      ['servers/ruby/haveapi.gemspec', "spec.name = 'unrelated'\n"],
      ['servers/ruby/haveapi.gemspec', "spec.name = 'haveapi'\nspec.add_dependency 'haveapi-client', '~> 0.30.3'\n"]
    ].each do |path, value|
      expect { described_class.capture(contents('0.30.2').merge(path => value)) }.to raise_error(error)
    end
  end

  it 'retains actual worker input receipts and rejects mismatched loaded local components' do
    # Provide owned lock bytes at the input boundary. The production worker still
    # refuses a missing root lock; component-only CI need not install that bundle.
    Dir.mktmpdir('haveapi-release-locks-') do |harness|
      FileUtils.mkdir_p(File.join(harness, 'servers/ruby'))
      File.write(File.join(harness, 'Gemfile.lock'), "controlled tooling lock\n")
      File.write(File.join(harness, 'servers/ruby/Gemfile.lock'), "controlled server lock\n")
      FileUtils.mkdir_p(File.join(harness, 'clients/rust'))
      File.write(File.join(harness, 'clients/rust/Gemfile.lock'), "controlled Rust lock\n")
      stub_const('HaveAPI::RustClient::VERSION', HaveAPI::VERSION) unless defined?(HaveAPI::RustClient::VERSION)
      stub_const('HaveAPI::Performance::ROOT', harness)
      ordinary = JSON.parse(JSON.generate(HaveAPI::Performance::Worker.inputs(root, 'quick')))
      preparation = ordinary.fetch('json_preparation')
      expect(preparation.fetch('declarations').values).to all(eq('exact-development-pin'))
      expect(ordinary.fetch('manifests').slice(*described_class::JSON_GEMFILES)).to eq(preparation.fetch('normalized_sha256'))
      expect do
        described_class.validate_json_preparation(ordinary, 'files_sha256' => preparation.fetch('raw_sha256'))
      end.not_to raise_error
      %w[HaveAPI::VERSION HaveAPI::Client::VERSION HaveAPI::RustClient::VERSION].each do |name|
        stub_const(name, '0.30.2')
      end
      HaveAPI::Performance::BENCHMARK_INPUTS.each do |path|
        FileUtils.mkdir_p(File.dirname(File.join(harness, path)))
        FileUtils.cp(File.join(root, path), File.join(harness, path))
      end
      with_maintenance_source do |source|
        captured = HaveAPI::Performance::Worker.inputs(source, 'quick', release: true)
        expect(captured[:locks]).to have_key('clients/rust/Gemfile.lock')
        expect(captured[:manifests]).to have_key('clients/rust/Gemfile')
        expect(captured.fetch(:release_versions)).to eq(described_class.capture(contents('0.30.2')))
        benchmark = JSON.parse(JSON.generate(HaveAPI::Performance::Worker.inputs(source, 'quick', release: true, benchmark: true)))
        expect(benchmark.fetch('manifests')).not_to have_key('flake.lock')
        expect(benchmark.fetch('contributor_flakes')).to have_key('flake.lock')
        expect(described_class.validate_inputs(benchmark, { 'files_sha256' => benchmark.fetch('release_versions').fetch('raw_sha256') }, 'quick')).to eq('0.30.2')
      end
      Dir.mktmpdir('haveapi-release-inputs-') do |source|
        contents('0.30.99').each do |path, value|
          FileUtils.mkdir_p(File.dirname(File.join(source, path)))
          File.write(File.join(source, path), value)
        end
        expect do
          HaveAPI::Performance::Worker.inputs(source, 'quick', release: true)
        end.to raise_error(error, /Wrong loaded local package version/)
      end
    end
  end

  def framework_footer(version)
    %(<p class="text-right">Generated by <a href="https://github.com/vpsfreecz/haveapi">HaveAPI</a> v#{version}</p>)
  end

  def served_html
    server = HaveAPI::DocumentationPerformanceFixture.build(resource_count: 1, actions_per_resource: 1)
    response = Rack::MockRequest.new(server.app).get('http://example.test/benchmark/api/v1/',
                                                     'HTTP_HOST' => 'example.test', 'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64('admin:fixture-only')}")
    expect(response.status).to eq(200)
    response.body
  end

  def html_samples(served: nil)
    samples, budget_json = PerformanceSamples.fixture
    samples['release_lineage'] = proof.merge('candidate_sha' => samples.fetch('candidate_sha'))
    normalized = nil
    samples.fetch('sources').each do |role, source|
      receipt = described_class.capture(contents(role == 'baseline' ? '0.30.1' : '0.30.2'))
      source['files_sha256'].merge!(receipt.fetch('raw_sha256'))
      inputs = { 'manifests' => receipt.fetch('normalized_sha256'), 'locks' => samples.fetch('inputs').fetch('locks'),
                 'release_versions' => receipt }
      normalized ||= described_class.graph(inputs)
      samples.fetch('observations').each_value do |observation|
        next unless observation.fetch('source').fetch('root') == source.fetch('root')

        observation['inputs'] = inputs
      end
    end
    samples['inputs'] = normalized
    id = 'docs.html_resources'
    samples['inventory'].first['id'] = id
    item = samples.fetch('cases').first
    item['id'] = id
    (item.fetch('self_pairs') + item.fetch('pairs')).each do |pair|
      %w[baseline candidate].each do |role|
        sample = pair.fetch(role)
        own = samples.fetch('observations').fetch(sample.fetch('observation')).fetch('inputs').fetch('release_versions').fetch('own_version')
        body = if served
                 source_version = File.read(File.join(root, 'VERSION')).strip
                 served.gsub("https://webui.haveapi.org/v#{source_version}/#", "https://webui.haveapi.org/v#{own}/#")
                       .sub(framework_footer(source_version), framework_footer(own))
               else
                 "<p>PUBLIC_SAMPLE_0 init-python-sync init-examples</p><a\n href=\"https://webui.haveapi.org/v#{own}/#http%3A%2F%2Fexample.test\">Connect</a>#{framework_footer(own)}"
               end
        digest = Digest::SHA256.hexdigest(body)
        sample['bodies'] = { digest => { 'body' => body, 'canonical_body' => nil } }
        sample['outputs'] = [{ 'http_status' => 200, 'envelope_status' => nil, 'body_bytes' => body.bytesize, 'body_sha256' => digest, 'count' => sample.fetch('operations'),
                               'canonical_sha256' => Digest::SHA256.hexdigest(described_class.html(body, own)),
                               'comparison' => { 'kind' => 'own-webui-href', 'own_version' => own } }]
      end
    end
    budgets = JSON.parse(budget_json)
    budgets['profiles']['quick'].first['id'] = id
    samples['budget_sha256'] = Digest::SHA256.hexdigest(JSON.generate(budgets))
    [samples, budgets]
  end

  def compare(samples, budgets)
    HaveAPI::Performance::Comparator.new(samples, budgets, budget_sha256: samples.fetch('budget_sha256')).compare
  end

  it 'replays distinct raw bodies and input hashes through the narrow normalization' do
    samples, budgets = html_samples
    expect(compare(samples, budgets).fetch('status')).to eq('pass')
    pair = samples.fetch('cases').first.fetch('pairs').first
    expect(pair['baseline']['outputs'].first['body_sha256']).not_to eq(pair['candidate']['outputs'].first['body_sha256'])
    expect(pair['baseline']['outputs'].first['canonical_sha256']).to eq(pair['candidate']['outputs'].first['canonical_sha256'])
  end

  it 'accepts real served footer/version changes and rejects a forged digest through the replay CLI' do
    samples, budgets = html_samples(served: served_html)
    Dir.mktmpdir('haveapi-release-replay-') do |directory|
      policy = File.join(directory, 'budget.json')
      input = File.join(directory, 'samples.json')
      File.write(policy, JSON.generate(budgets))
      # The CLI runs unchanged, with the same owned mini-history policy as this
      # example. No production defect switch or fixture-history dependency exists.
      fixture = File.join(directory, 'history.json')
      File.write(fixture, JSON.generate(git_fixture))
      adapter = File.join(directory, 'replay.rb')
      File.write(adapter, <<~RUBY)
        require #{File.join(root, 'servers/ruby/benchmarks/endpoints.rb').inspect}
        history = JSON.parse(File.read(ARGV.shift))
        performance = HaveAPI::Performance
        performance.send(:remove_const, :REFERENCE)
        performance.const_set(:REFERENCE, history.fetch('reference'))
        { 'MAPPED' => 'mapped', 'METADATA' => 'metadata', 'TREES' => 'trees', 'DELTA' => 'delta_sha256' }.each do |name, key|
          performance::Release.send(:remove_const, name)
          performance::Release.const_set(name, history.fetch(key))
        end
        exit performance::CLI.new(ARGV).execute
      RUBY
      [false, true].each do |tampered|
        samples['cases'].first['pairs'].first['candidate']['outputs'].first['canonical_sha256'] = 'f' * 64 if tampered
        File.write(input, JSON.generate(samples))
        _output, _errors, status = Open3.capture3(RbConfig.ruby, adapter, fixture, 'compare',
                                                  '--input', input, '--budgets', policy,
                                                  '--output', File.join(directory, tampered ? 'tampered' : 'valid'))
        expect(status.exitstatus).to eq(tampered ? 3 : 0)
      end
    end
  end

  it 'normalizes the actual worker HTML outside timing and retains its raw bytes' do
    own = '0.30.2'
    body = "<a href=\"https://webui.haveapi.org/v#{own}/#api\">Connect</a>#{framework_footer(own)}"
    scenario = HaveAPI::Performance::DocumentationScenario.allocate
    allow(scenario).to receive(:reset!)
    allow(scenario).to receive_messages(call: Rack::MockResponse.new(200, {}, body),
                                        validate!: { http_status: 200, envelope_status: nil, body_bytes: body.bytesize,
                                                     body_sha256: Digest::SHA256.hexdigest(body), canonical_sha256: Digest::SHA256.hexdigest(body) },
                                        counters: { operations: [{ queries: 0, authorizations: 0, executions: 0 }] })
    with_maintenance_source do |source|
      worker = HaveAPI::Performance::Worker.new('source_root' => source, 'release_versions' => true)
      worker.instance_variable_set(:@current_workload, 'docs.html_resources')
      result = worker.measure(scenario, 1)
      output = result.fetch(:outputs).first
      expect(output.fetch('comparison')).to include('own_version' => own)
      expect(result.fetch(:bodies).values.first.fetch(:body)).to eq(body)
      expect(output.fetch('canonical_sha256')).to eq(Digest::SHA256.hexdigest(described_class.html(body, output['comparison']['own_version'])))
    end
  end

  it 'leaves lookalike attributes, other URLs, JSON and example code byte exact' do
    [
      '<a data-href="https://webui.haveapi.org/v0.30.2/#api">',
      '<a href="https://other.test/v0.30.2/#api">',
      '<a href="https://webui.haveapi.org.evil/v0.30.2/#api">',
      '<a href="http://webui.haveapi.org/v0.30.2/#api">',
      '<a href="https://webui.haveapi.org/v0.30.3/#api">',
      '<a href="https://webui.haveapi.org/v0.30.2/other#api">',
      '{"version":"0.30.2","url":"https://webui.haveapi.org/v0.30.2/#api"}',
      '&lt;a href="https://webui.haveapi.org/v0.30.2/#api"&gt;',
      '<code><a href="https://webui.haveapi.org/v0.30.2/#api"></a></code>',
      '<PRE><a href="https://webui.haveapi.org/v0.30.2/#api"></a></PRE>',
      '<script>let x = \'<a href="https://webui.haveapi.org/v0.30.2/#api">\';</script>',
      '<!-- <a href="https://webui.haveapi.org/v0.30.2/#api"> -->'
    ].each do |body|
      expect(described_class.html(body + framework_footer('0.30.2'), '0.30.2')).to eq(body + framework_footer('0.30.PATCH'))
    end
  end

  it 'requires one exact framework footer matching the verified own version' do
    footer = framework_footer('0.30.2')
    [footer.sub('Generated by', 'Produced by'), footer.sub('github.com', 'other.test'),
     framework_footer('0.30.3'), footer + footer, '<p>No footer</p>',
     "<code>#{footer}</code>", "<!-- #{footer} -->", "<div data-example='#{footer}'></div>"].each do |body|
      expect { described_class.html(body, '0.30.2') }.to raise_error(error, /footer/)
    end
  end

  it 'preserves footer-like examples, attributes and unrelated version strings' do
    footer = framework_footer('0.30.2')
    opaque = "<pre>#{footer}</pre><code>v0.30.2</code><!-- #{footer} --><div data-example='#{footer}'></div>"
    expect(described_class.html(opaque + footer, '0.30.2')).to eq(opaque + framework_footer('0.30.PATCH'))
    samples, budgets = html_samples(served: served_html)
    sample = samples['cases'].first['pairs'].first['candidate']
    body = "#{sample['bodies'].values.first['body']}<code>v0.30.2</code>"
    digest = Digest::SHA256.hexdigest(body)
    sample['bodies'] = { digest => { 'body' => body, 'canonical_body' => nil } }
    sample['outputs'].first.merge!('body_sha256' => digest, 'body_bytes' => body.bytesize,
                                   'canonical_sha256' => Digest::SHA256.hexdigest(described_class.html(body, '0.30.2')))
    expect { compare(samples, budgets) }.to raise_error(error, /Response identity/)
  end

  it 'rejects forged raw/normalized hashes, output differences and unverified input contents on replay' do
    %w[raw normalized marker graph raw_graph api auth panels].each do |fault|
      samples, budgets = html_samples
      sample = samples.fetch('cases').first.fetch('pairs').first.fetch('candidate')
      observation = samples.fetch('observations').fetch(sample.fetch('observation'))
      output = sample.fetch('outputs').first
      case fault
      when 'raw' then sample['bodies'].values.first['body'] += 'tampered'
      when 'normalized' then output['canonical_sha256'] = 'f' * 64
      when 'marker' then output['comparison']['own_version'] = '0.30.1'
      when 'graph' then observation['inputs']['release_versions']['normalized_sha256']['Gemfile'] = 'f' * 64
      when 'raw_graph'
        receipt = described_class.capture(observation['inputs']['release_versions']['contents'].merge('Gemfile' => '# replaced'))
        observation['inputs'].merge!('release_versions' => receipt, 'manifests' => receipt['normalized_sha256'])
      else
        raw = sample['bodies'].values.first['body']
        body = case fault
               when 'api' then "#{raw}<pre>{\"version\":\"0.30.2\"}</pre>"
               when 'auth' then "#{raw}ADMIN_ONLY_REQUEST"
               else raw.sub('init-examples', '')
               end
        digest = Digest::SHA256.hexdigest(body)
        sample['bodies'] = { digest => { 'body' => body, 'canonical_body' => nil } }
        output.merge!('body_sha256' => digest, 'body_bytes' => body.bytesize,
                      'canonical_sha256' => Digest::SHA256.hexdigest(described_class.html(body, '0.30.2')))
      end
      expect { compare(samples, budgets) }.to raise_error(error), fault
    end
  end
end
