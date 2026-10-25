require 'spec_helper'
require 'open3'
require 'tmpdir'
require 'fileutils'
require_relative '../../benchmarks/endpoints'
require_relative 'support/samples'

describe HaveAPI::Performance::Worker do
  def live_worker(control, rack_env: 'development')
    root = File.expand_path('../../../..', __dir__)
    sqlite = %w[query sqlite-clean].include?(control)
    spec = { 'id' => sqlite ? 'sqlite.page' : 'api.public_get',
             'dimensions' => sqlite ? { 'rows' => 128, 'page_size' => 32 } : {} }
    request = { source_root: root, source_sha: HaveAPI::Performance::REFERENCE, profile: 'quick',
                counts: { HaveAPI::Performance::Identity.key(spec) => 3 } }
    environment = ENV.keys.grep(/\ABUNDLE|\ABUNDLER|\ARUBY(?:OPT|LIB)\z/).to_h { |key| [key, nil] }
    environment['RACK_ENV'] = rack_env
    Dir.mktmpdir('haveapi-worker-control-') do |harness|
      paths = %w[benchmarks/endpoints.rb benchmarks/performance_compare.rb spec/performance/support/live_worker.rb Gemfile.lock]
      paths += HaveAPI::Performance::FIXTURE_PATHS.map { |name| "test_support/#{name}" }
      paths.each do |path|
        destination = File.join(harness, 'servers/ruby', path)
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(File.join(root, 'servers/ruby', path), destination)
      end
      # Ordinary server CI resolves only its component bundle. Prove these
      # isolated controls also run with no root tooling Gemfile.lock present.
      expect(File.exist?(File.join(harness, 'Gemfile.lock'))).to be(false)
      output, errors, status = Open3.capture3(environment, RbConfig.ruby, File.join(harness, 'servers/ruby/spec/performance/support/live_worker.rb'),
                                              control, stdin_data: JSON.generate(request))
      [status.exitstatus, status.success? ? JSON.parse(output) : errors]
    end
  end

  it 'measures real isolated requests and detects live allocation amplification' do
    clean_code, clean = live_worker('clean')
    fault_code, fault = live_worker('allocation')
    expect(clean_code).to eq(0), clean.inspect
    expect(fault_code).to eq(0), fault.inspect
    root = File.expand_path('../../../..', __dir__)
    expect(clean['inputs']['manifests']).to eq('servers/ruby/Gemfile' => Digest::SHA256.file(File.join(root, 'servers/ruby/Gemfile')).hexdigest)
    expect(clean['inputs']['locks']).to eq('servers/ruby/Gemfile.lock' => Digest::SHA256.file(File.join(root, 'servers/ruby/Gemfile.lock')).hexdigest)
    expect(clean['cases'].first['outputs'].length).to eq(3)
    expect(fault['cases'].first['allocated_objects']).to be > clean['cases'].first['allocated_objects'] + 4000
    expect(fault['source']['loaded_sources'].keys).to include('servers/ruby/lib/haveapi/server.rb',
                                                              'servers/ruby/lib/haveapi/model_adapters/active_record.rb',
                                                              'clients/ruby/lib/haveapi/client/client.rb')
    # Replay the live worker's complete per-operation records through the real
    # comparator CLI. Timing traces are controlled here; the allocation fault is
    # measured in the isolated process rather than manufactured arithmetic.
    samples, budget_json = PerformanceSamples.fixture
    budget = JSON.parse(budget_json)
    baseline = clean['cases'].first.merge('observation' => 'baseline', 'wall_seconds' => 0.001, 'cpu_seconds' => 0.001)
    candidate = fault['cases'].first.merge('observation' => 'candidate', 'wall_seconds' => 0.001, 'cpu_seconds' => 0.001)
    entry = samples['cases'].first
    entry['iterations'] = 3
    entry['self_pairs'].each do |pair|
      name = pair['workload_order'] == 'forward' ? 'baseline' : 'baseline-reverse'
      pair.merge!('baseline' => baseline.merge('observation' => name), 'candidate' => baseline.merge('observation' => name))
    end
    entry['pairs'].each do |pair|
      suffix = pair['workload_order'] == 'forward' ? '' : '-reverse'
      pair.merge!('baseline' => baseline.merge('observation' => "baseline#{suffix}"),
                  'candidate' => candidate.merge('observation' => "candidate#{suffix}"))
    end
    reference = baseline['allocated_objects']
    budget['profiles']['quick'].first.merge!('reference_allocations' => reference, 'allocation_ceiling' => (reference * 1.25).ceil + 32)
    budget_json = JSON.generate(budget)
    samples['budget_sha256'] = Digest::SHA256.hexdigest(budget_json)
    Dir.mktmpdir('haveapi-live-allocation-') do |directory|
      File.write(File.join(directory, 'samples.json'), JSON.generate(samples))
      File.write(File.join(directory, 'budget.json'), budget_json)
      _out, _err, status = Open3.capture3(RbConfig.ruby, File.expand_path('../../benchmarks/endpoints.rb', __dir__), 'compare',
                                          '--input', File.join(directory, 'samples.json'), '--budgets', File.join(directory, 'budget.json'),
                                          '--output', File.join(directory, 'report'))
      expect(status.exitstatus).to eq(1)
    end
  end

  it 'fails the actual worker CLI on an extra live SQLite query and wrong output' do
    %w[query wrong-output].each do |control|
      code, evidence = live_worker(control)
      expect(code).to eq(3)
      expect(evidence).to include(control == 'query' ? 'counter' : 'Unexpected output')
    end
  end

  it 'sets its policy before loading SQLite and emits clean JSON with absent or development RACK_ENV' do
    [nil, 'development'].each do |rack_env|
      code, result = live_worker('sqlite-clean', rack_env:)
      expect(code).to eq(0), result.inspect
      expect(result['runtime_policy']).to eq(HaveAPI::Performance::RUNTIME_POLICY)
      expect(result['host'].values).to all(be_a(String))
      expect(result['cases'].first['counters']['operations']).to eq(Array.new(3) do
        { 'queries' => 1, 'authorizations' => 1, 'executions' => 1 }
      end)
    end
  end

  it 'keeps production input validation strict when the root lock is absent but the server lock exists' do
    source = File.expand_path('../../../..', __dir__)
    Dir.mktmpdir('haveapi-production-inputs-') do |harness|
      FileUtils.mkdir_p(File.join(harness, 'servers/ruby'))
      FileUtils.cp(File.join(source, 'servers/ruby/Gemfile.lock'), File.join(harness, 'servers/ruby/Gemfile.lock'))
      stub_const('HaveAPI::Performance::ROOT', harness)
      expect { described_class.inputs(source, 'quick') }.to raise_error(HaveAPI::Performance::ContractError,
                                                                        "Missing resolved lock #{harness}/Gemfile.lock")
    end
  end

  it 'validates every response after the timed loop' do
    scenario = Class.new do
      attr_reader :calls, :validations

      def reset!(iterations:)
        @iterations = iterations
        @calls = 0
        @validations = []
      end

      def call
        @calls += 1
        Rack::MockResponse.new(200, {}, JSON.generate(status: true))
      end

      def validate!(response, index:)
        raise 'Validation ran during request loop' unless @calls == @iterations

        @validations << index
        HaveAPI::Performance::Identity.json(response)
      end

      def counters
        { operations: Array.new(@iterations) { { queries: 0, authorizations: 0, executions: 0 } } }
      end
    end.new
    result = described_class.new({}).measure(scenario, 4)
    expect(scenario.validations).to eq([0, 1, 2, 3])
    expect(result[:operations]).to eq(4)
  end

  it 'normalizes source proofs before direct run comparison and preserves replay composition' do
    samples, budget_json = PerformanceSamples.fixture
    budgets = JSON.parse(budget_json)
    Dir.mktmpdir('haveapi-run-composition-') do |directory|
      policy = File.join(directory, 'budgets.json')
      output = File.join(directory, 'result')
      File.write(policy, budget_json)
      %w[baseline candidate].each do |role|
        root = File.join(directory, role)
        Dir.mkdir(root)
        samples['sources'][role]['root'] = root
      end
      cli = HaveAPI::Performance::CLI.new(['run', '--baseline-root', samples['sources']['baseline']['root'],
                                           '--baseline-sha', samples['baseline_sha'],
                                           '--candidate-root', samples['sources']['candidate']['root'],
                                           '--candidate-sha', samples['candidate_sha'], '--budgets', policy, '--output', output])
      # Control source verification and worker replies, retaining the real run
      # assembly, child protocol validation, direct comparator and report path.
      allow(cli).to receive(:git).and_return('')
      allow(cli).to receive(:verify_source) { |role| samples['sources'].fetch(role).transform_keys(&:to_sym) }
      allow(Open3).to receive(:capture3) do |*_arguments, stdin_data:|
        request = JSON.parse(stdin_data)
        role = samples['sources'].find { |_name, source| source['sha'] == request['source_sha'] }.first
        source = samples['sources'].fetch(role).merge('loaded_sources' => { 'server.rb' => 'd' * 64 })
        observation = samples['observations'].fetch(role).merge('source' => source, 'fixture_sha256' => described_class.fixture_hashes,
                                                                'workload_order' => request['workload_order'])
        item = samples['cases'].first['pairs'].first.fetch(role).merge(samples['inventory'].first)
        item = item.merge('wall_seconds' => 0.150) if request['counts'].empty?
        result = observation.merge('inventory' => samples['inventory'], 'cases' => [item])
        [JSON.generate(result), '', instance_double(Process::Status, success?: true)]
      end
      expect(cli.execute).to eq(0)
      retained = JSON.parse(File.read(File.join(output, 'samples.json')))
      expect(retained['sources']).to eq(samples['sources'])
      report = HaveAPI::Performance::Comparator.new(retained, budgets, budget_sha256: Digest::SHA256.hexdigest(budget_json)).compare
      expect(report['status']).to eq('pass')
    end
  end

  it 'fails closed on unavailable immutable source and preserves existing output evidence' do
    Dir.mktmpdir('haveapi-runner-') do |directory|
      output = File.join(directory, 'existing')
      Dir.mkdir(output)
      sentinel = File.join(output, 'report.json')
      File.write(sentinel, 'existing evidence')
      cli = HaveAPI::Performance::CLI.new(['compare', '--input', 'absent', '--budgets', 'absent', '--output', output])
      expect(cli.execute).to eq(3)
      expect(File.read(sentinel)).to eq('existing evidence')
      missing = File.join(directory, 'missing')
      budget = File.join(directory, 'budgets.json')
      File.write(budget, PerformanceSamples.fixture.last)
      cli = HaveAPI::Performance::CLI.new(['run', '--baseline-root', directory, '--baseline-sha', '0' * 40,
                                           '--candidate-root', directory, '--candidate-sha', '1' * 40,
                                           '--budgets', budget, '--output', missing])
      expect(cli.execute).to eq(3)
      report = JSON.parse(File.read(File.join(missing, 'report.json')))
      expect(report['error']['message']).to include('Source SHA must be full immutable SHA')
      expect(report.values_at('baseline_sha', 'candidate_sha')).to eq(['0' * 40, '1' * 40])
      equal = HaveAPI::Performance::CLI.new(['run', '--baseline-root', directory, '--baseline-sha', 'a' * 40,
                                             '--candidate-root', directory, '--candidate-sha', 'a' * 40,
                                             '--budgets', budget, '--output', File.join(directory, 'equal')])
      expect(equal.execute).to eq(3)
    end
  end
end
