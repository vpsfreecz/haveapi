require 'spec_helper'
require 'tmpdir'
require 'open3'
require_relative 'support/samples'

describe HaveAPI::Performance::Comparator do
  def compare_cli(samples, budgets)
    Dir.mktmpdir('haveapi-comparator-') do |directory|
      input = File.join(directory, 'samples.json')
      policy = File.join(directory, 'budgets.json')
      output = File.join(directory, 'result')
      File.write(input, JSON.generate(samples))
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
  end

  it 'blocks an agreed meaningful slowdown for either clock independently' do
    %w[wall_seconds cpu_seconds].each do |metric|
      samples, budgets = PerformanceSamples.fixture
      samples['cases'].first['pairs'].each { |pair| pair['candidate'][metric] = 0.0015 }
      code, report = compare_cli(samples, budgets)
      expect(code).to eq(1)
      expect(report['cases'].first['timing'][metric]['regression_agreement']).to eq(9)
    end
  end

  it 'blocks noisy inconclusive results without widening the budget' do
    samples, budgets = PerformanceSamples.fixture
    samples['cases'].first['self_pairs'].first['candidate']['wall_seconds'] = 0.003
    code, report = compare_cli(samples, budgets)
    expect(code).to eq(2)
    expect(report['status']).to eq('inconclusive')
  end

  it 'requires eight of nine agreements and fourteen of fifteen weekly agreements' do
    samples, budgets = PerformanceSamples.fixture
    samples['cases'].first['pairs'].first(7).each { |pair| pair['candidate']['wall_seconds'] = 0.0015 }
    expect(compare_cli(samples, budgets).first).to eq(2)
    samples['cases'].first['pairs'][7]['candidate']['wall_seconds'] = 0.0015
    expect(compare_cli(samples, budgets).first).to eq(1)

    weekly, budget_json = PerformanceSamples.fixture(profile: 'weekly')
    weekly['cases'].first['pairs'].first(13).each { |pair| pair['candidate']['wall_seconds'] = 0.0015 }
    expect(compare_cli(weekly, budget_json).first).to eq(2)
    weekly['cases'].first['pairs'][13]['candidate']['wall_seconds'] = 0.0015
    expect(compare_cli(weekly, budget_json).first).to eq(1)
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
    expect(compare_cli(samples, budgets).first).to eq(0)
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
      when 'queries' then target['counters']['operations'].first['queries'] = 1
      when 'authorizations' then target['counters']['operations'].first['authorizations'] = 0
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
