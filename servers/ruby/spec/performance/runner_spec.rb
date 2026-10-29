require 'spec_helper'
require 'open3'
require 'tmpdir'
require 'fileutils'
require_relative '../../benchmarks/endpoints'
require_relative '../../../../utils/performance_ci'
require_relative '../../../../clients/ruby/lib/haveapi/client/version'
require_relative '../../../../clients/rust/lib/haveapi/rust_client/version'
require_relative 'support/samples'
require_relative '../../test_support/performance_endpoint_fixture'
require_relative '../../test_support/documentation_performance_fixture'

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
    expect(clean['cases'].first['outputs'].length).to eq(1)
    expect(clean['cases'].first['outputs'].first['count']).to eq(3)
    expect(fault['cases'].first['allocated_objects']).to be > clean['cases'].first['allocated_objects'] + 4000
    expect(fault['source']['loaded_sources'].keys).to include('servers/ruby/lib/haveapi/server.rb',
                                                              'servers/ruby/lib/haveapi/model_adapters/active_record.rb',
                                                              'clients/ruby/lib/haveapi/client/client.rb')
    # Replay the live worker's validated compact summary through the real
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
      expect(result['cases'].first['counters']).to eq('operations' => 3, 'record' => { 'queries' => 1, 'authorizations' => 1, 'executions' => 1 })
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

  it 'retains the single benchmark bundle and raw unused contributor flakes without library locks' do
    root = File.expand_path('../../../..', __dir__)
    inputs = JSON.parse(JSON.generate(described_class.inputs(root, 'quick', benchmark: true)))
    tool = inputs.fetch('benchmark')
    expect(tool.keys).to match_array(HaveAPI::Performance::BENCHMARK_INPUTS)
    expect(inputs.fetch('locks')).to eq('servers/ruby/benchmarks/Gemfile.lock' => tool.fetch('servers/ruby/benchmarks/Gemfile.lock').fetch('sha256'))
    expect(inputs.fetch('manifests')).to have_key('.ruby-version')
    expect(inputs.fetch('manifests')).not_to have_key('flake.lock')
    expect(inputs.fetch('contributor_flakes').keys).to match_array(%w[flake.nix flake.lock])
    tool.each do |path, input|
      expect(input.fetch('content')).to eq(File.read(File.join(root, path)))
      expect(input.fetch('sha256')).to eq(Digest::SHA256.hexdigest(input.fetch('content')))
    end
  end

  it 'rejects changed Ruby and unavailable calibrated dependencies before starting workers' do
    samples, json = PerformanceSamples.fixture
    Dir.mktmpdir('haveapi-runtime-guard-') do |directory|
      budget = File.join(directory, 'budgets.json')
      cli = HaveAPI::Performance::CLI.new(['run', '--baseline-root', directory, '--baseline-sha', samples['baseline_sha'],
                                           '--candidate-root', directory, '--candidate-sha', samples['candidate_sha'],
                                           '--budgets', budget, '--output', File.join(directory, 'result')])
      cli.send(:parse)
      File.write(budget, json)
      allow(cli).to receive(:child)
      expect { cli.send(:run_samples, 'f' * 64) }.to raise_error(HaveAPI::Performance::ContractError, 'Calibration Ruby mismatch')
      budgets = JSON.parse(json)
      budgets['environment']['weekly']['ruby'] = JSON.parse(JSON.generate(described_class.new({}).environment.fetch(:ruby)))
      budgets['environment']['weekly']['gems'] = { 'haveapi-missing-calibrated-gem' => { 'version' => '99.0', 'platform' => 'ruby' } }
      File.write(budget, JSON.generate(budgets))
      expect { cli.send(:run_samples, 'f' * 64) }.to raise_error(HaveAPI::Performance::ContractError, /Missing calibrated dependency/)
      expect(cli).not_to have_received(:child)
    end
  end

  it 'limits the nonancestor runner exception to an exact quick push event pair' do
    samples, = PerformanceSamples.fixture
    Dir.mktmpdir('haveapi-push-guard-') do |directory|
      event = File.join(directory, 'selection.json')
      selection = samples.slice('baseline_sha', 'candidate_sha').merge('event_name' => 'push', 'profile' => 'quick',
                                                                       'push_pair' => { 'event_name' => 'push', 'before' => samples['baseline_sha'], 'after' => samples['candidate_sha'] })
      %w[valid changed missing weekly].each do |control|
        value = Marshal.load(Marshal.dump(selection))
        value['push_pair']['before'] = 'c' * 40 if control == 'changed'
        value.delete('push_pair') if control == 'missing'
        File.write(event, JSON.generate(value))
        cli = HaveAPI::Performance::CLI.new(['run', '--baseline-root', directory, '--baseline-sha', samples['baseline_sha'],
                                             '--candidate-root', directory, '--candidate-sha', samples['candidate_sha'],
                                             '--profile', control == 'weekly' ? 'weekly' : 'quick', '--push-event', event,
                                             '--budgets', '/unused', '--output', '/unused'])
        cli.send(:parse)
        allow(cli).to receive(:verify_runtime)
        allow(HaveAPI::Performance).to receive(:gemspec)
        allow(cli).to receive(:verify_source) { |role| samples['sources'].fetch(role) }
        allow(cli).to receive(:ancestor?).and_return(false)
        allow(HaveAPI::Performance::Release).to receive(:lineage).and_return(nil)
        allow(cli).to receive(:child).and_raise(HaveAPI::Performance::ContractError, 'pilot boundary')
        expect { cli.send(:run_samples, 'f' * 64) }.to raise_error(HaveAPI::Performance::ContractError,
                                                                   control == 'valid' ? 'pilot boundary' : /push|Push|Weekly/)
        expect(cli).not_to have_received(:child) unless control == 'valid'
      end
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

  it 'reuses immutable body proof within a sample while checking every operation and resetting between samples' do
    scenario = HaveAPI::PerformanceFixtures::Endpoints.build(id: 'api.list', dimensions: { rows: 32 })
    responses = []
    allow(scenario).to(receive(:call).and_wrap_original { |call| call.call.tap { |response| responses << response } })
    allow(scenario).to receive(:validate!).and_call_original
    allow(scenario).to receive(:validate_body!).and_call_original
    worker = described_class.new({})
    result = worker.measure(scenario, 8)
    expect(scenario).to have_received(:validate!).exactly(8).times
    expect(scenario).to have_received(:validate_body!).once
    expect(result[:bodies].length).to eq(1)
    expect(result[:outputs].length).to eq(1)
    expect(result[:outputs].first['count']).to eq(8)
    expect(result[:counters]).to eq(operations: 8, record: { queries: 0, authorizations: 1, executions: 1 })
    retained = result[:bodies].values.first
    original = retained[:body].dup
    responses.first.body.replace('changed after validation')
    expect(retained[:body]).to eq(original)
    expect { retained[:canonical_body]['response']['probe'].first['count'] = 9 }.to raise_error(FrozenError)
    following = worker.measure(scenario, 3)
    expect(following[:outputs].length).to eq(result[:outputs].length)
    expect(following[:outputs].first['count']).to eq(3)
    expect(scenario).to have_received(:validate_body!).twice
  ensure
    scenario&.close
  end

  it 'rejects later changed bodies, metadata, collisions and execution records despite an earlier valid body' do
    %w[body status header collision counter].each do |fault|
      scenario = HaveAPI::PerformanceFixtures::Endpoints.build(id: 'api.basic_get', dimensions: {})
      scenario.reset!(iterations: 1)
      valid = scenario.call
      digest = Digest::SHA256.hexdigest(valid.body)
      broken = valid.body.sub('"count":0', '"count":"wrong"')
      calls = 0
      allow(scenario).to receive(:call).and_wrap_original do |call|
        response = call.call
        calls += 1
        next response unless calls == 3

        case fault
        when 'body', 'collision' then Rack::MockResponse.new(200, response.headers, broken)
        when 'status' then Rack::MockResponse.new(403, response.headers, response.body)
        when 'header' then Rack::MockResponse.new(200, { 'content-type' => 'text/plain' }, response.body)
        else
          scenario.instance_variable_get(:@state).operations[2][:executions] = 0
          response
        end
      end
      if fault == 'collision'
        allow(Digest::SHA256).to receive(:hexdigest).and_call_original
        allow(Digest::SHA256).to receive(:hexdigest).with(broken).and_return(digest)
      end
      expect { described_class.new({}).measure(scenario, 3) }.to raise_error(StandardError)
      scenario.close
    end
  end

  it 'does not reuse proof across authorization roles or trust a forged first canonical body' do
    admin = HaveAPI::PerformanceFixtures::Endpoints.build(id: 'api.list', dimensions: { rows: 1, user: 'admin' })
    member = HaveAPI::PerformanceFixtures::Endpoints.build(id: 'api.list', dimensions: { rows: 1, user: 'member' })
    worker = described_class.new({})
    administrative = worker.measure(admin, 2)
    body = administrative[:bodies].values.first.fetch(:body)
    allow(member).to receive(:call).and_wrap_original do |call|
      response = call.call
      Rack::MockResponse.new(200, response.headers, body)
    end
    expect { worker.measure(member, 2) }.to raise_error(/Unexpected output/)
    allow(admin).to receive(:validate_body!).and_wrap_original do |validate, response|
      validate.call(response).tap { |identity| identity[:canonical_body]['response']['probe'].first['count'] = 3 }
    end
    expect { worker.measure(admin, 2) }.to raise_error(HaveAPI::Performance::ContractError, %r{raw/canonical})
    expect { worker.measure(admin, 100_001) }.to raise_error(HaveAPI::Performance::ContractError, /iteration/)
  ensure
    admin&.close
    member&.close
  end

  it 'keeps documentation body proofs within their user/sample and checks uncalled indexes and auth every time' do
    admin = HaveAPI::Performance::DocumentationScenario.new(id: 'docs.html_resources', dimensions: { size: 1, user: 'admin' })
    member = HaveAPI::Performance::DocumentationScenario.new(id: 'docs.html_resources', dimensions: { size: 1, user: 'member' })
    worker = described_class.new({})
    [admin, member].each do |scenario|
      allow(scenario).to receive(:validate_body!).and_call_original
      worker.measure(scenario, 2)
      expect(scenario).to have_received(:validate_body!).once
    end
    member.reset!(iterations: 2)
    response = member.call
    expect { member.validate!(response, index: 1) { raise 'uncalled body proof' } }.to raise_error(HaveAPI::Performance::ContractError, /uncalled/)
    member.instance_variable_get(:@operations).first[:authorizations] = 0
    expect { member.validate!(response, index: 0) { raise 'unchecked counter' } }.to raise_error(HaveAPI::Performance::ContractError, /counters/)
    administrative = worker.measure(admin, 1)[:bodies].values.first[:body]
    allow(member).to receive(:call).and_wrap_original do |call|
      response = call.call
      Rack::MockResponse.new(200, response.headers, administrative)
    end
    expect { worker.measure(member, 2) }.to raise_error(HaveAPI::Performance::ContractError, /authorization/)
  ensure
    admin&.close
    member&.close
  end

  it 'selects shared counts above twenty thousand with one adjustment and retains cap inadequacy' do
    [false, true].each do |under_cap|
      pilot_seconds = under_cap ? 0.000001 : 0.000025
      samples, = PerformanceSamples.fixture
      cli = HaveAPI::Performance::CLI.new(['run', '--baseline-root', '/controlled/baseline', '--baseline-sha', samples['baseline_sha'],
                                           '--candidate-root', '/controlled/candidate', '--candidate-sha', samples['candidate_sha'],
                                           '--budgets', '/unused', '--output', '/unused'])
      cli.send(:parse)
      allow(cli).to receive(:verify_runtime)
      allow(HaveAPI::Performance).to receive(:gemspec)
      allow(cli).to receive(:verify_source) { |role| samples['sources'].fetch(role) }
      allow(cli).to receive(:ancestor?).and_return(true)
      allow(HaveAPI::Performance::Release).to receive(:lineage).and_return(nil)
      requests = []
      item = samples['inventory'].first
      key = HaveAPI::Performance::Identity.key(item)
      allow(cli).to receive(:child) do |role, counts, label, *_order|
        requests << [role, counts.dup, label]
        cli.instance_variable_set(:@common, samples.slice('environment', 'inputs'))
        duration = if label == 'pilot'
                     pilot_seconds
                   elsif label == 'calibration-adjusted'
                     0.000009
                   else
                     0.00001
                   end
        duration = 0.000001 if under_cap
        duration = 0.9 if role == 'candidate'
        { 'inventory' => [item], 'cases' => [item.merge('wall_seconds' => duration)] }
      end
      result = cli.send(:run_samples, samples['budget_sha256'])['cases'].first
      expect(result['iterations']).to eq(100_000)
      expect(result['pilot']['capped']).to be(true)
      expect(result['pilot']['adequate_signal']).to eq(!under_cap)
      expect(requests.count { |request| request.last == 'calibration-adjusted' }).to eq(under_cap ? 0 : 1)
      requests.reject { |request| %w[pilot calibration].include?(request.last) }.each do |_role, counts, _label|
        expect(counts.fetch(key)).to eq(100_000)
      end
    end
  end

  it 'detects a live repeated-operation slowdown well below tenfold with per-request normalization' do
    scenario_class = Class.new do
      def initialize(delay)
        @delay = delay
      end

      def reset!(iterations:)
        @iterations = iterations
      end

      def call
        sleep @delay
        Rack::MockResponse.new(200, {}, JSON.generate(status: true, response: { zero: 0, no: false, empty: '', null: nil }))
      end

      def validate!(response, index:)
        HaveAPI::Performance::Identity.json(response)
      end

      def counters
        { operations: Array.new(@iterations) { { queries: 0, authorizations: 1, executions: 1 } } }
      end
    end
    measured = [0.003, 0.0045].map do |delay|
      JSON.parse(JSON.generate(described_class.new({}).measure(scenario_class.new(delay), 256)))
    end
    samples, json = PerformanceSamples.fixture
    item = samples['cases'].first
    item['iterations'] = 256
    (item['self_pairs'] + item['pairs']).each_with_index do |pair, index|
      %w[baseline candidate].each do |role|
        observation = pair[role]['observation']
        trace = measured[index < item['self_pairs'].length || role == 'baseline' ? 0 : 1]
        pair[role] = trace.merge('observation' => observation)
      end
    end
    budget = JSON.parse(json)
    allocations = measured.first.fetch('allocated_objects')
    budget['profiles']['quick'].first.merge!('reference_allocations' => allocations,
                                             'allocation_ceiling' => (allocations * 1.25).ceil + 32)
    json = JSON.generate(budget)
    samples['budget_sha256'] = Digest::SHA256.hexdigest(json)
    report = HaveAPI::Performance::Comparator.new(samples, budget, budget_sha256: samples['budget_sha256']).compare
    expect(report['status']).to eq('regression')
    expect(report['cases'].first['timing']['wall_seconds']['classification']).to eq('regression')
    expect(measured.first['stages']['request_seconds']).to be >= 0.75
    expect(measured.last['wall_seconds'] / measured.first['wall_seconds']).to be_between(1.20, 3.0)
    warn JSON.generate(control: 'live repeated slowdown', operations: 256,
                       baseline_batch_seconds: measured.first['stages']['request_seconds'],
                       candidate_batch_seconds: measured.last['stages']['request_seconds'])
  end

  [false, true].each do |expensive|
    it "preserves source/replay composition and common #{expensive ? 'expensive' : 'cheap'} count/warmup policy" do
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
        allow(cli).to receive(:verify_runtime)
        allow(HaveAPI::Performance).to receive(:gemspec)
        allow(cli).to receive_messages(git: '', ancestor?: true)
        allow(HaveAPI::Performance::Release).to receive(:lineage).and_return(nil)
        allow(cli).to receive(:verify_source) { |role| samples['sources'].fetch(role).transform_keys(&:to_sym) }
        requests = []
        allow(cli).to receive(:capture_worker) do |_environment, worker_request, label|
          request = JSON.parse(JSON.generate(worker_request))
          requests << [label, request]
          role = samples['sources'].find { |_name, source| source['sha'] == request['source_sha'] }.first
          source = samples['sources'].fetch(role).merge('loaded_sources' => { 'server.rb' => 'd' * 64 })
          observation = samples['observations'].fetch(role).merge('source' => source, 'fixture_sha256' => described_class.fixture_hashes,
                                                                  'workload_order' => request['workload_order'])
          items = samples['cases'].map do |entry|
            count = request['counts'].fetch(HaveAPI::Performance::Identity.key(entry), 1)
            sample = entry['pairs'].first.fetch(role)
            sample.merge(entry.slice('id', 'dimensions')).merge('operations' => count,
                                                                'outputs' => sample['outputs'].map { |example| example.merge('count' => count) },
                                                                'counters' => { 'operations' => count, 'record' => sample['counters']['record'] },
                                                                'wall_seconds' => if expensive
                                                                                    2.0
                                                                                  else
                                                                                    (label == 'pilot' ? 0.9 : 0.25)
                                                                                  end, 'cpu_seconds' => if expensive
                                                                                                          2.0
                                                                                                        else
                                                                                                          (label == 'pilot' ? 0.9 : 0.25)
                                                                                                        end)
          end
          result = observation.merge('schema_version' => HaveAPI::Performance::SAMPLE_SCHEMA, 'inventory' => samples['inventory'], 'cases' => items)
          [JSON.generate(result), '', instance_double(Process::Status, success?: true)]
        end
        expect(cli.execute).to eq(0)
        retained = JSON.parse(File.read(File.join(output, 'samples.json')))
        expect(retained['sources']).to eq(samples['sources'])
        saved_report = JSON.parse(File.read(File.join(output, 'report.json')))
        expect(saved_report.dig('comparison', 'samples_sha256')).to eq(Digest::SHA256.file(File.join(output, 'samples.json')).hexdigest)
        expect(saved_report['harness_sha256']).to eq(retained['harness_sha256'])
        report = HaveAPI::Performance::Comparator.new(retained, budgets, budget_sha256: Digest::SHA256.hexdigest(budget_json)).compare
        expect(report['status']).to eq('pass')
        expect(requests.map(&:first).count('calibration-adjusted')).to eq(expensive ? 0 : 1)
        expect(retained['cases'].map { |item| item['iterations'] }).to all(eq(expensive ? 1 : 4))
        expect(retained['cases'].map { |item| item['pilot']['baseline_batch_seconds'] }).to all(eq(expensive ? 2.0 : 1.0))
        requests.each do |label, request|
          expect(request['benchmark']).to be(true)
          next if %w[pilot calibration].include?(label)

          expect(request['counts'].values).to all(eq(expensive ? 1 : 4))
          expect(request['warmup_counts'].values).to all(eq(expensive ? 0 : 1))
        end
      end
    end
  end

  it 'terminates and reaps stalled API, SQLite and documentation batches with source and phase diagnostics' do
    stub_const('HaveAPI::Performance::REQUEST_LIMIT_SECONDS', 0.05)
    %w[api.public_get sqlite.page docs.html_rust].zip(%w[pilot warmup-0 measured]).each do |workload, phase|
      Dir.mktmpdir('haveapi-watchdog-') do |directory|
        cli = HaveAPI::Performance::CLI.new([])
        cli.instance_variable_set(:@output, directory)
        program = <<~RUBY
          require 'json'
          request = JSON.parse(STDIN.read)
          progress = IO.for_fd(request.fetch('progress_fd'))
          STDOUT.sync = STDERR.sync = true
          puts Process.pid
          warn 'before stalled request'
          progress.puts(JSON.generate(state: 'request', workload: #{workload.inspect}, phase: #{phase.inspect}))
          progress.flush
          sleep 10
        RUBY
        allow(cli).to receive(:worker_command).and_return([RbConfig.ruby, '-e', program])
        expect do
          cli.send(:capture_worker, {}, { source_sha: 'a' * 40 }, 'controlled')
        end.to raise_error(HaveAPI::Performance::WorkerTimeout) { |error|
          expect(error.details).to include(kind: 'request_batch_timeout', workload:, source_sha: 'a' * 40, limit_seconds: 0.05)
          expect(error.details[:phase]).to include(phase)
        }
        pid = File.read(File.join(directory, 'controlled.json')).to_i
        expect(pid).to be > 0
        expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
        expect(File.read(File.join(directory, 'controlled.stderr.log'))).to include('before stalled request')
      end
    end
  end

  it 'distinguishes a worker setup timeout from request work' do
    stub_const('HaveAPI::Performance::SETUP_LIMIT_SECONDS', 0.05)
    Dir.mktmpdir('haveapi-setup-watchdog-') do |directory|
      cli = HaveAPI::Performance::CLI.new([])
      cli.instance_variable_set(:@output, directory)
      allow(cli).to receive(:worker_command).and_return([RbConfig.ruby, '-e', 'sleep 10'])
      expect do
        cli.send(:capture_worker, {}, { source_sha: 'a' * 40 }, 'setup-control')
      end.to raise_error(HaveAPI::Performance::WorkerTimeout) { |error|
        expect(error.details[:kind]).to eq('worker_setup_timeout')
      }
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
      allow(cli).to receive(:verify_runtime)
      expect(cli.execute).to eq(3)
      report = JSON.parse(File.read(File.join(missing, 'report.json')))
      expect(report['error']['message']).to include('Source SHA must be full immutable SHA')
      expect(report.values_at('baseline_sha', 'candidate_sha')).to eq(['0' * 40, '1' * 40])
      expect(report).not_to have_key('harness_sha256')
      expect(report.fetch('comparison')).not_to have_key('samples_sha256')
      equal = HaveAPI::Performance::CLI.new(['run', '--baseline-root', directory, '--baseline-sha', 'a' * 40,
                                             '--candidate-root', directory, '--candidate-sha', 'a' * 40,
                                             '--budgets', budget, '--output', File.join(directory, 'equal')])
      expect(equal.execute).to eq(3)
    end
  end

  it 'checks declared Ruby and runtime requirements against installed tools including unloaded rake' do
    campaign = HaveAPI::PerformanceCI::Campaign.new(repository: instance_double(HaveAPI::PerformanceCI::Repository),
                                                    selection: {}, evidence: '/unused', sources: '/unused')
    spec = { 'ruby' => '>= 3.2', 'dependencies' => [['rake', 'runtime', '>= 13.0'], ['haveapi-client', 'runtime', '~> 0.30.0']] }
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return([JSON.generate(spec), '', status])
    expect(campaign.send(:gemspec, '/source', 'servers/ruby/haveapi.gemspec')).to eq(spec)
    changed = spec.merge('ruby' => '>= 99')
    allow(Open3).to receive(:capture3).and_return([JSON.generate(changed), '', status])
    expect { campaign.send(:gemspec, '/source', 'servers/ruby/haveapi.gemspec') }.to raise_error(HaveAPI::PerformanceCI::Error, /Benchmark Ruby/)
    changed = spec.merge('dependencies' => [['rake', 'runtime', '>= 99']])
    allow(Open3).to receive(:capture3).and_return([JSON.generate(changed), '', status])
    expect { campaign.send(:gemspec, '/source', 'servers/ruby/haveapi.gemspec') }.to raise_error(HaveAPI::PerformanceCI::Error, /Benchmark dependencies/)
  end

  it 'rejects unsupported Ruby or gem requirements in either direct source before the first child' do
    samples, = PerformanceSamples.fixture
    Dir.mktmpdir('haveapi-source-requirements-') do |directory|
      roots = %w[baseline candidate].to_h { |role| [role, File.join(directory, role)] }
      paths = HaveAPI::Performance::Release::VERSIONS.map { |path, name| "#{path.split('/lib/').first}/#{name}.gemspec" }
      valid = <<~RUBY
        Gem::Specification.new do |spec|
          spec.name = 'haveapi-fixture'
          spec.version = '1.0.0'
          spec.required_ruby_version = '>= 3.2'
          spec.add_dependency 'rake', '>= 13.0'
        end
      RUBY
      roots.each_value do |root|
        paths.each do |path|
          FileUtils.mkdir_p(File.dirname(File.join(root, path)))
          File.write(File.join(root, path), valid)
        end
      end
      %w[baseline candidate].product(%w[valid ruby dependency]).each do |role, fault|
        path = File.join(roots.fetch(role), paths.last)
        text = case fault
               when 'ruby' then valid.sub('>= 3.2', '>= 99')
               when 'dependency' then valid.sub('>= 13.0', '>= 99')
               else valid
               end
        File.write(path, text)
        cli = HaveAPI::Performance::CLI.new(['run', '--baseline-root', roots['baseline'], '--baseline-sha', samples['baseline_sha'],
                                             '--candidate-root', roots['candidate'], '--candidate-sha', samples['candidate_sha'],
                                             '--budgets', '/unused', '--output', '/unused'])
        cli.send(:parse)
        allow(cli).to receive(:verify_runtime)
        allow(cli).to receive(:verify_source) { |name| { root: roots.fetch(name), sha: samples.fetch("#{name}_sha") } }
        allow(cli).to receive(:ancestor?).and_return(true)
        allow(HaveAPI::Performance::Release).to receive(:lineage).and_return(nil)
        allow(cli).to receive(:child).and_raise(HaveAPI::Performance::ContractError, 'pilot boundary')
        expect { cli.send(:run_samples, 'f' * 64) }.to raise_error(HaveAPI::Performance::ContractError,
                                                                   fault == 'valid' ? 'pilot boundary' : /Benchmark Ruby|Benchmark dependencies/)
        expect(cli).not_to have_received(:child) unless fault == 'valid'
        File.write(path, valid)
      end
    end
  end
end
