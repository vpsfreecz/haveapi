require 'spec_helper'
require 'tmpdir'
require 'open3'
require_relative 'support/samples'

describe HaveAPI::Performance::Comparator do
  def compare_cli(samples, budgets, sample_bytes: JSON.generate(samples))
    Dir.mktmpdir('haveapi-comparator-') do |directory|
      input = File.join(directory, 'samples.json')
      policy = File.join(directory, 'budgets.json')
      output = File.join(directory, 'result')
      File.binwrite(input, sample_bytes)
      File.write(policy, budgets)
      _stdout, _stderr, status = Open3.capture3(RbConfig.ruby, File.expand_path('../../benchmarks/endpoints.rb', __dir__),
                                                'compare', '--input', input, '--budgets', policy, '--output', output)
      [status.exitstatus, JSON.parse(File.read(File.join(output, 'report.json')))]
    end
  end

  def replace_raw_body(sample, body)
    output = sample['outputs'].first
    raw = sample['bodies'].delete(output['body_sha256'])
    digest = Digest::SHA256.hexdigest(body)
    sample['bodies'][digest] = raw.merge('body' => body)
    output.merge!('body_sha256' => digest, 'body_bytes' => body.bytesize)
  end

  def replace_response(sample, body, json: true)
    replace_raw_body(sample, body)
    canonical = json ? JSON.parse(body) : nil
    sample['bodies'].values.first['canonical_body'] = canonical
    sample['outputs'].first.merge!('envelope_status' => json ? canonical.fetch('status') : nil,
                                   'canonical_sha256' => json ? HaveAPI::Performance::Identity.digest(canonical) : Digest::SHA256.hexdigest(body))
  end

  def rebind_source(samples, role, sha)
    samples["#{role}_sha"] = sha
    samples['sources'][role]['sha'] = sha
    samples['observations'].each_value do |observation|
      observation['source']['sha'] = sha if observation['source']['root'] == samples['sources'][role]['root']
    end
  end

  it 'passes controlled AA traces through the actual CLI' do
    samples, budgets = PerformanceSamples.fixture
    code, report = compare_cli(samples, budgets)
    expect(code).to eq(0)
    expect(report['status']).to eq('pass')
    expect(report['cases'].first['timing'].keys).to eq(%w[wall_seconds cpu_seconds])
    expect(report['schema_version']).to eq(2)
    expect(report['cases'].first['correctness']).to include('status' => 'pass', 'operations_per_sample' => 1)
    expect(JSON.generate(report)).not_to include('canonical_body', 'body_sha256', 'self_pairs', 'observations', 'loaded_sources')
  end

  it 'attributes replay success and loaded-input errors to exact input/comparator bytes and the original measurement harness' do
    samples, budgets = PerformanceSamples.fixture
    [false, true].each do |broken|
      samples['schema_version'] = broken ? 1 : 2
      bytes = "#{JSON.pretty_generate(samples)}\n"
      code, report = compare_cli(samples, budgets, sample_bytes: bytes)
      expect(code).to eq(broken ? 3 : 0)
      expect(report['harness_sha256']).to eq('e' * 64)
      expect(report.values_at('baseline_sha', 'candidate_sha', 'budget_sha256')).to eq(samples.values_at('baseline_sha', 'candidate_sha', 'budget_sha256'))
      expect(report['comparison']).to eq('policy' => 'per-revision-response-stability-v1',
                                         'comparator_sha256' => Digest::SHA256.file(File.expand_path('../../benchmarks/performance_compare.rb', __dir__)).hexdigest,
                                         'samples_sha256' => Digest::SHA256.hexdigest(bytes))
    end
    code, report = compare_cli(samples, budgets, sample_bytes: '{')
    expect(code).to eq(3)
    expect(report).not_to have_key('harness_sha256')
    expect(report.dig('comparison', 'samples_sha256')).to eq(Digest::SHA256.hexdigest('{'))
  end

  it 'classifies stable changed JSON and HTML normally without changing performance budgets' do
    samples, budgets = PerformanceSamples.fixture
    samples['cases'].each do |item|
      html = item['id'].start_with?('docs.')
      (item['self_pairs'] + item['pairs']).each do |pair|
        %w[baseline candidate].each do |role|
          actual = samples['observations'][pair[role]['observation']]['source']['sha']
          value = actual == samples['baseline_sha'] ? 'before' : 'after'
          body = html ? "<!doctype html><html><body>#{value}</body></html>" : JSON.generate(status: true, response: value)
          replace_response(pair[role], body, json: !html)
        end
      end
    end
    code, report = compare_cli(samples, budgets)
    expect(code).to eq(0)
    expect(report['status']).to eq('pass')
    expect(report['cases'].map { |item| item['responses'].slice('raw_changed', 'canonical_changed') }).to all(eq('raw_changed' => true, 'canonical_changed' => true))
    %w[wall_seconds cpu_seconds allocated_objects].each do |metric|
      changed = Marshal.load(Marshal.dump(samples))
      changed['cases'].first['pairs'].each { |pair| pair['candidate'][metric] = metric == 'allocated_objects' ? 140 : 3.0 }
      regression_code, regression_report = compare_cli(changed, budgets)
      expect(regression_code).to eq(1), metric
      expect(regression_report['status']).to eq('regression')
    end
  end

  it 'rejects canonical variation within a source including the second baseline/self column' do
    %w[self_pairs pairs].each do |group|
      samples, budgets = PerformanceSamples.fixture
      replace_response(samples['cases'].first[group].last['candidate'], '{"status":true,"response":"changed"}')
      code, report = compare_cli(samples, budgets)
      expect(code).to eq(3)
      expected_sha = samples[group == 'self_pairs' ? 'baseline_sha' : 'candidate_sha']
      expect(report.dig('error', 'message')).to eq("Response identity differs within revision #{expected_sha}")
    end
  end

  it 'replays benchmark inputs with different unused contributor flakes and rejects tampered consumed or source inputs' do
    %w[quick weekly].each do |profile|
      samples, budgets = PerformanceSamples.fixture(profile:)
      tool = HaveAPI::Performance::BENCHMARK_INPUTS.to_h do |path|
        content = "controlled #{path}\n"
        [path, { 'content' => content, 'sha256' => Digest::SHA256.hexdigest(content) }]
      end
      samples.fetch('observations').each_value do |observation|
        role = observation.fetch('source').fetch('sha') == samples['baseline_sha'] ? 'baseline' : 'candidate'
        inputs = Marshal.load(Marshal.dump(observation.fetch('inputs')))
        inputs['benchmark'] = tool
        inputs['locks'] = { 'servers/ruby/benchmarks/Gemfile.lock' => tool.fetch('servers/ruby/benchmarks/Gemfile.lock').fetch('sha256') }
        inputs['contributor_flakes'] = %w[flake.nix flake.lock].to_h { |path| [path, { 'content' => "#{role} #{path}" }] }
        inputs['contributor_flakes'].each do |path, input|
          samples['sources'][role]['files_sha256'][path] = Digest::SHA256.hexdigest(input.fetch('content'))
        end
        inputs['manifests']['.ruby-version'] = Digest::SHA256.hexdigest('3.2.0')
        samples['sources'][role]['files_sha256']['.ruby-version'] = inputs['manifests']['.ruby-version']
        observation['inputs'] = inputs
      end
      samples['inputs'] = HaveAPI::Performance::Release.graph(samples['observations']['baseline']['inputs'])
      expect(compare_cli(samples, budgets).first).to eq(0)
      %w[tool lock raw-flake declaration ruby].each do |fault|
        changed = Marshal.load(Marshal.dump(samples))
        inputs = changed['observations']['candidate']['inputs']
        case fault
        when 'tool' then inputs['benchmark']['servers/ruby/benchmarks/shell.nix']['content'] << 'tampered'
        when 'lock' then inputs['locks']['servers/ruby/benchmarks/Gemfile.lock'] = 'f' * 64
        when 'raw-flake' then inputs['contributor_flakes']['flake.nix']['content'] << 'tampered'
        when 'declaration' then inputs['manifests']['servers/ruby/Gemfile'] = 'f' * 64
        else inputs['manifests']['.ruby-version'] = 'f' * 64
        end
        expect(compare_cli(changed, budgets).first).to eq(3), "#{profile}:#{fault}"
      end
    end
  end

  it 'rejects unsupported sample formats without converting historical evidence' do
    samples, budgets = PerformanceSamples.fixture
    samples['schema_version'] = 1
    code, report = compare_cli(samples, budgets)
    expect(code).to eq(3)
    expect(report.dig('error', 'message')).to include('Unsupported samples schema; expected 2')
  end

  it 'blocks an agreed meaningful slowdown for either clock independently' do
    %w[wall_seconds cpu_seconds].each do |metric|
      samples, budgets = PerformanceSamples.fixture
      samples['cases'].first['pairs'].each { |pair| pair['candidate'][metric] = 3.0 }
      code, report = compare_cli(samples, budgets)
      expect(code).to eq(1)
      expect(report['cases'].first['timing'][metric]['regression_agreement']).to eq(5)
    end
  end

  it 'retains noisy inconclusive diagnostics without failing readiness' do
    samples, budgets = PerformanceSamples.fixture
    samples['cases'].first['self_pairs'].first['candidate']['wall_seconds'] = 6.0
    code, report = compare_cli(samples, budgets)
    expect(code).to eq(0)
    expect(report['status']).to eq('inconclusive')
  end

  it 'requires four of five quick agreements and six of seven weekly agreements' do
    %w[quick weekly].each do |profile|
      samples, budgets = PerformanceSamples.fixture(profile:)
      agreement = HaveAPI::Performance::PROFILES.fetch(profile).fetch(:agreement)
      samples['cases'].first['pairs'].first(agreement - 1).each { |pair| pair['candidate']['wall_seconds'] = 3.0 }
      code, report = compare_cli(samples, budgets)
      expect(code).to eq(0)
      expect(report['status']).to eq('inconclusive')
      samples['cases'].first['pairs'][agreement - 1]['candidate']['wall_seconds'] = 3.0
      expect(compare_cli(samples, budgets).first).to eq(1)
    end
  end

  it 'uses the stricter weekly budget on the same fifteen percent increase' do
    %w[quick weekly].each do |profile|
      samples, budgets = PerformanceSamples.fixture(profile:)
      samples['cases'].first['pairs'].each { |pair| pair['candidate']['wall_seconds'] = 2.30 }
      expect(compare_cli(samples, budgets).first).to eq(profile == 'quick' ? 0 : 1)
    end
  end

  it 'detects a cheap-request twenty-five percent regression using the batch floor' do
    samples, budgets = PerformanceSamples.fixture
    item = samples['cases'].first
    item['iterations'] = 25_000
    (item['self_pairs'] + item['pairs']).each do |pair|
      pair.each_value do |sample|
        next unless sample.is_a?(Hash)

        sample['operations'] = 25_000
        sample['outputs'].first['count'] = 25_000
        sample['counters']['operations'] = 25_000
        sample['wall_seconds'] = sample['cpu_seconds'] = 0.00004
      end
    end
    item['pairs'].each { |pair| pair['candidate']['wall_seconds'] = 0.00005 }
    expect(compare_cli(samples, budgets).first).to eq(1)
  end

  it 'validates distinct examples and rejects malformed compact counts, identities and counter summaries' do
    samples, json = PerformanceSamples.fixture
    budget = JSON.parse(json)
    spec = samples['cases'].first
    sample = Marshal.load(Marshal.dump(spec['pairs'].first['candidate']))
    sample['operations'] = 4
    sample['outputs'].first['count'] = 4
    sample['counters']['operations'] = 4
    comparator = described_class.new(samples, budget, budget_sha256: samples['budget_sha256'])
    body = sample['bodies'].values.first['body']
    allow(HaveAPI::Performance::Identity).to receive(:parse).and_call_original
    comparator.send(:validate_sample, sample, 4, budget['profiles']['quick'].first, spec)
    expect(HaveAPI::Performance::Identity).to have_received(:parse).with(body).once
    %w[http_status envelope_status body_bytes body_sha256 canonical_sha256 comparison counter missing zero negative float total counter_count duplicate unreferenced].each do |fault|
      broken = Marshal.load(Marshal.dump(sample))
      output = broken['outputs'].last
      case fault
      when 'http_status' then output[fault] = 403
      when 'envelope_status' then output[fault] = false
      when 'body_bytes' then output[fault] += 1
      when 'comparison' then output[fault] = { 'kind' => 'own-webui-href', 'own_version' => '0.30.2' }
      when 'counter' then broken['counters']['record']['authorizations'] = 0
      when 'missing' then broken['counters'].delete('record')
      when 'zero' then output['count'] = 0
      when 'negative' then output['count'] = -1
      when 'float' then output['count'] = 4.0
      when 'total' then output['count'] = 3
      when 'counter_count' then broken['counters']['operations'] = 4.0
      when 'duplicate'
        output['count'] = 2
        broken['outputs'] << output.dup
      when 'unreferenced'
        other_body = '{"status":true}'
        broken['bodies'][Digest::SHA256.hexdigest(other_body)] = { 'body' => other_body, 'canonical_body' => JSON.parse(other_body) }
      else output[fault] = '0' * 64
      end
      expect { comparator.send(:validate_sample, broken, 4, budget['profiles']['quick'].first, spec) }.to raise_error(StandardError)
    end
    # A second sample must independently prove its retained body again.
    comparator.send(:validate_sample, sample, 4, budget['profiles']['quick'].first, spec)
    expect(HaveAPI::Performance::Identity).to have_received(:parse).with(body).at_least(:twice)
  end

  it 'rejects raw/canonical disagreement and duplicate JSON on a reused body and rejects counts above the shared cap' do
    %w[canonical duplicate cap].each do |fault|
      samples, json = PerformanceSamples.fixture
      spec = samples['cases'].first
      sample = spec['pairs'].first['candidate']
      if fault == 'canonical'
        sample['bodies'].values.first['canonical_body']['response']['zero'] = 1
      elsif fault == 'duplicate'
        body = sample['bodies'].values.first['body'].sub('"status":true', '"status":false,"status":true')
        replace_raw_body(sample, body)
      else
        spec['iterations'] = 100_001
      end
      comparator = described_class.new(samples, JSON.parse(json), budget_sha256: samples['budget_sha256'])
      expect { comparator.compare }.to raise_error(HaveAPI::Performance::ContractError)
    end
  end

  it 'compares response occurrence totals within each revision without retaining request order' do
    samples, json = PerformanceSamples.fixture
    spec = samples['cases'].first
    spec['iterations'] = 3
    (spec['self_pairs'] + spec['pairs']).each do |pair|
      %w[baseline candidate].each do |role|
        sample = pair[role]
        output = sample['outputs'].first
        body = sample['bodies'].values.first['body'].sub('"zero":0', '"zero":100')
        canonical = JSON.parse(body)
        digest = Digest::SHA256.hexdigest(body)
        sample['bodies'][digest] = { 'body' => body, 'canonical_body' => canonical }
        sample['operations'] = 3
        sample['outputs'] << output.merge('body_sha256' => digest, 'body_bytes' => body.bytesize,
                                          'canonical_sha256' => HaveAPI::Performance::Identity.digest(canonical), 'count' => 2)
        sample['counters']['operations'] = 3
      end
    end
    comparator = described_class.new(samples, JSON.parse(json), budget_sha256: samples['budget_sha256'])
    report = comparator.compare
    expect(report['status']).to eq('pass')
    original_bytes = spec['pairs'].first['baseline']['outputs'].first['body_bytes']
    expect(report['cases'].first.dig('responses', 'bytes_per_request', 'baseline')).to be_within(0.00001).of(original_bytes + (4.0 / 3))
    spec['pairs'].last['candidate']['outputs'].reverse!
    expect(comparator.compare['status']).to eq('pass')
    spec['pairs'].each { |pair| pair['candidate']['outputs'].each { |example| example['count'] = 3 - example['count'] } }
    report = comparator.compare
    expect(report['status']).to eq('pass')
    expect(report['cases'].first.dig('responses', 'canonical_changed')).to be(true)
    spec['pairs'].last['candidate']['outputs'].each { |example| example['count'] = 3 - example['count'] }
    expect { comparator.compare }.to raise_error(HaveAPI::Performance::ContractError, /Response identity/)
  end

  it 'rejects retained runaway request batches even if both sources are equally slow' do
    samples, budgets = PerformanceSamples.fixture
    item = samples['cases'].first
    (item['self_pairs'] + item['pairs']).each do |pair|
      %w[baseline candidate].each { |role| pair[role]['wall_seconds'] = 100.0 }
    end
    code, report = compare_cli(samples, budgets)
    expect(code).to eq(3)
    expect(report.dig('error', 'message')).to include('Request batch exceeds 30.0s')
  end

  it 'rejects raw integer/float drift even when forged raw metadata is consistent' do
    [[0, 0.0], [0.0, 0]].each do |original, changed|
      samples, budgets = PerformanceSamples.fixture(zero: original)
      target = samples['cases'].first['pairs'].first['candidate']
      body = JSON.parse(target['bodies'].values.first['body'])
      body['response']['zero'] = changed
      replace_raw_body(target, JSON.generate(body))
      code, report = compare_cli(samples, budgets)
      expect(code).to eq(3)
      expect(report.dig('error', 'message')).to include('Raw/canonical output values differ')
    end
  end

  it 'allows raw map-order changes through the actual CLI' do
    samples, budgets = PerformanceSamples.fixture
    target = samples['cases'].first['pairs'].first['candidate']
    body = JSON.parse(target['bodies'].values.first['body'])
    body['response'] = body['response'].to_a.reverse.to_h
    replace_raw_body(target, JSON.generate(body.to_a.reverse.to_h))
    code, report = compare_cli(samples, budgets)
    expect(code).to eq(0)
    expect(report['cases'].first['responses']).to include('raw_changed' => true, 'canonical_changed' => false)
    expect(report['cases'].first.dig('responses', 'bytes_per_request', 'delta')).to eq(0)
  end

  it 'reports weighted byte deltas from baseline/candidate pairs without self-pair bias or a raw determinism requirement' do
    samples, budgets = PerformanceSamples.fixture
    item = samples['cases'].first
    baseline_bytes = item['pairs'].first['baseline']['outputs'].first['body_bytes']
    item['self_pairs'].each do |pair|
      %w[baseline candidate].each { |role| replace_raw_body(pair[role], " #{pair[role]['bodies'].values.first['body']}") }
    end
    item['pairs'].last(2).each do |pair|
      replace_raw_body(pair['candidate'], "  #{pair['candidate']['bodies'].values.first['body']}")
    end
    code, report = compare_cli(samples, budgets)
    expect(code).to eq(0)
    response = report['cases'].first['responses']
    expect(response).to include('raw_changed' => true, 'canonical_changed' => false)
    expect(response['bytes_per_request']).to include('baseline' => baseline_bytes, 'candidate' => baseline_bytes + 0.8)
    expect(response['bytes_per_request']['delta']).to be_within(0.00001).of(0.8)
    expect(response['bytes_per_request']['delta_percent']).to be_within(0.00001).of(80.0 / baseline_bytes)
  end

  it 'rejects identical source SHAs even with consistently rebound provenance' do
    samples, budgets = PerformanceSamples.fixture
    rebind_source(samples, 'candidate', samples['baseline_sha'])
    code, report = compare_cli(samples, budgets)
    expect(code).to eq(3)
    expect(report.dig('error', 'message')).to include('Baseline and candidate must differ')
  end

  it 'requires the fixed weekly baseline and accepts valid fixed-reference evidence' do
    samples, budgets = PerformanceSamples.fixture(profile: 'weekly')
    expect(compare_cli(samples, budgets).first).to eq(0)
    rebind_source(samples, 'baseline', 'a' * 40)
    code, report = compare_cli(samples, budgets)
    expect(code).to eq(3)
    expect(report.dig('error', 'message')).to include('Weekly baseline must be the fixed reference')
  end

  it 'requires both the percentage and absolute timing thresholds' do
    samples, budgets = PerformanceSamples.fixture
    samples['cases'].first['pairs'].each do |pair|
      pair['baseline']['wall_seconds'] = 0.0001
      pair['candidate']['wall_seconds'] = 0.00013
    end
    expect(compare_cli(samples, budgets).first).to eq(0)
  end

  it 'blocks allocation growth and the independent fixed reference ceiling' do
    samples, budgets = PerformanceSamples.fixture
    samples['cases'].first['pairs'].each { |pair| pair['candidate']['allocated_objects'] = 140 }
    expect(compare_cli(samples, budgets).first).to eq(1)
    samples['cases'].first['pairs'].each do |pair|
      pair['baseline']['allocated_objects'] = 180
      pair['candidate']['allocated_objects'] = 180
    end
    expect(compare_cli(samples, budgets).first).to eq(1)
  end

  it 'requires full Rust cases and their relative allocation and authorization contracts' do
    %w[missing allocations authorization].each do |fault|
      samples, budgets = PerformanceSamples.fixture
      case fault
      when 'missing'
        samples['inventory'].pop
        samples['cases'].pop
      when 'allocations'
        samples['cases'].last['pairs'].each { |pair| pair['candidate']['allocated_objects'] = 200 }
      else
        samples['cases'].last['pairs'].first['candidate']['counters']['record']['authorizations'] -= 1
      end
      expect(compare_cli(samples, budgets).first).to eq(fault == 'allocations' ? 1 : 3)
    end
  end

  it 'blocks uncalibrated reference budgets' do
    samples, json = PerformanceSamples.fixture
    budgets = JSON.parse(json)
    budgets.delete('calibration')
    json = JSON.generate(budgets)
    samples['budget_sha256'] = Digest::SHA256.hexdigest(json)
    expect(compare_cli(samples, json).first).to eq(3)
  end

  it 'blocks missing cases, operations, dependency graphs and source provenance' do
    %w[cases outputs inputs sources].each do |missing|
      samples, budgets = PerformanceSamples.fixture
      case missing
      when 'cases' then samples['cases'].clear
      when 'outputs' then samples['cases'].first['pairs'].first['candidate']['outputs'].clear
      else samples.delete(missing)
      end
      expect(compare_cli(samples, budgets).first).to eq(3)
    end
  end

  it 'rejects missing or changed workload order and runtime policy' do
    %w[workload_order worker_order runtime_policy].each do |fault|
      samples, budgets = PerformanceSamples.fixture
      case fault
      when 'workload_order' then samples['cases'].first['pairs'][1]['workload_order'] = 'forward'
      when 'worker_order' then samples['observations']['candidate-reverse']['workload_order'] = 'forward'
      else samples['observations']['baseline']['runtime_policy']['timezone'] = 'local'
      end
      expect(compare_cli(samples, budgets).first).to eq(3)
    end
  end

  it 'blocks extra queries, lost authorizations, wrong output and changed dependency graphs' do
    %w[queries authorizations output environment].each do |fault|
      samples, budgets = PerformanceSamples.fixture
      target = samples['cases'].first['pairs'].first['candidate']
      case fault
      when 'queries' then target['counters']['record']['queries'] = 1
      when 'authorizations' then target['counters']['record']['authorizations'] = 0
      when 'output' then target['outputs'].first['canonical_sha256'] = '0' * 64
      else samples['observations']['candidate']['environment'] = {}
      end
      expect(compare_cli(samples, budgets).first).to eq(3)
    end
  end

  it 'preserves scalar types and array order while ignoring map order only' do
    identity = HaveAPI::Performance::Identity
    expect(identity.digest(a: 0, b: [false, '', nil])).to eq(identity.digest('b' => [false, '', nil], 'a' => 0))
    expect(identity.digest(a: 0)).not_to eq(identity.digest(a: 0.0))
    expect(identity.digest(a: [false, nil])).not_to eq(identity.digest(a: [nil, false]))
    expect { identity.digest(a: 0, 'a' => 1) }.to raise_error(HaveAPI::Performance::ContractError)
    ['{"status":false,"status":true}', '{"a":[{"b":1,"b":2}]}'].each do |json|
      expect { identity.parse(json) }.to raise_error(HaveAPI::Performance::ContractError, /Duplicate/)
    end
  end
end
