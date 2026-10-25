require 'json'
require 'digest'
require_relative '../../../benchmarks/performance_compare'

module PerformanceSamples
  def self.fixture(profile: 'quick', zero: 0)
    identity = HaveAPI::Performance::Identity
    policy = HaveAPI::Performance::PROFILES.fetch(profile)
    baseline_sha = profile == 'weekly' ? HaveAPI::Performance::REFERENCE : 'a' * 40
    body = JSON.generate(status: true, response: { zero:, no: false, empty: '', null: nil })
    digest = Digest::SHA256.hexdigest(body)
    output = { 'http_status' => 200, 'envelope_status' => true, 'body_bytes' => body.bytesize,
               'body_sha256' => digest, 'canonical_sha256' => identity.digest(JSON.parse(body)) }
    sample = { 'operations' => 1, 'wall_seconds' => 0.001, 'cpu_seconds' => 0.001, 'allocated_objects' => 100,
               'outputs' => [output], 'bodies' => { digest => { 'body' => body, 'canonical_body' => JSON.parse(body) } },
               'counters' => { 'operations' => [{ 'queries' => 0, 'authorizations' => 1, 'executions' => 1 }] } }
    spec = { 'id' => 'api.public_get', 'dimensions' => {} }
    environment = { 'ruby' => { 'version' => 'controlled-detector-trace' }, 'gems' => { 'test' => 'controlled' } }
    fixtures = { 'controlled' => 'f' * 64 }
    inputs = { 'locks' => { 'Gemfile.lock' => 'a' * 64 }, 'manifests' => { 'Gemfile' => 'b' * 64 } }
    sources = %w[baseline candidate].each_with_index.to_h do |role, index|
      [role, { 'root' => "/controlled/#{role}", 'sha' => index == 0 ? baseline_sha : 'b' * 40,
               'tree' => 'c' * 40, 'tracked_files' => 1, 'files_sha256' => { 'server.rb' => 'd' * 64 } }]
    end
    observations = sources.flat_map do |role, source|
      %w[forward reverse].map do |order|
        [order == 'forward' ? role : "#{role}-reverse",
         { 'source' => source.merge('loaded_sources' => { 'server.rb' => 'd' * 64 }),
           'environment' => environment, 'fixture_sha256' => fixtures, 'inputs' => inputs,
           'runtime_policy' => HaveAPI::Performance::RUNTIME_POLICY, 'workload_order' => order,
           'host' => { 'hostname' => 'controlled', 'os' => 'controlled', 'cpu' => 'controlled' } }]
      end
    end
    observations = observations.to_h
    pair = lambda do |index, self_pair|
      { 'order' => if self_pair
                     %w[baseline baseline]
                   else
                     (index.even? ? %w[baseline candidate] : %w[candidate baseline])
                   end,
        'workload_order' => index.even? ? 'forward' : 'reverse',
        'baseline' => sample.merge('observation' => index.even? ? 'baseline' : 'baseline-reverse'),
        'candidate' => sample.merge('observation' => "#{self_pair ? 'baseline' : 'candidate'}#{'-reverse' unless index.even?}") }
    end
    budget = { 'schema_version' => 1, 'reference_sha' => HaveAPI::Performance::REFERENCE, 'environment' => { profile => environment },
               'calibration' => { profile => { 'source_sha' => HaveAPI::Performance::REFERENCE, 'raw_sha256' => 'f' * 64,
                                               'warmup_batches' => 2, 'iterations' => 1, 'fixture_sha256' => fixtures, 'inputs' => inputs } },
               'profiles' => { profile => [spec.merge('reference_allocations' => 100, 'allocation_ceiling' => 157,
                                                      'counters' => sample['counters']['operations'].first)] } }
    budget_json = JSON.generate(budget)
    samples = { 'schema_version' => 1, 'profile' => profile, 'baseline_sha' => baseline_sha, 'candidate_sha' => 'b' * 40,
                'harness_sha256' => 'e' * 64, 'fixture_sha256' => fixtures,
                'budget_sha256' => Digest::SHA256.hexdigest(budget_json), 'environment' => environment,
                'inputs' => inputs, 'sources' => sources, 'observations' => observations, 'inventory' => [spec],
                'cases' => [spec.merge('iterations' => 1, 'self_pairs' => Array.new(policy[:self_pairs]) { |i| pair.call(i, true) },
                                       'pairs' => Array.new(policy[:pairs]) { |i| pair.call(i, false) })] }
    [JSON.parse(JSON.generate(samples)), budget_json]
  end
end
