require 'digest'
require 'json'

module HaveAPI
  module Performance
    REFERENCE = 'b85ec364057f536940d689b09e612512ffffaf82'.freeze
    PROFILES = { 'quick' => { self_pairs: 3, pairs: 9, agreement: 8 },
                 'weekly' => { self_pairs: 5, pairs: 15, agreement: 14 } }.freeze
    METRICS = %w[wall_seconds cpu_seconds allocated_objects].freeze
    COUNTERS = %w[queries authorizations executions].freeze
    RUNTIME_POLICY = { 'rack_env' => 'test', 'locale' => 'C.UTF-8', 'timezone' => 'UTC', 'yjit' => false, 'rjit' => false }.freeze
    class ContractError < StandardError; end

    def self.validate_source_pair(profile:, baseline_sha:, candidate_sha:)
      raise ContractError, 'Baseline and candidate must differ' if baseline_sha == candidate_sha
      return unless profile == 'weekly' && baseline_sha != REFERENCE

      raise ContractError, 'Weekly baseline must be the fixed reference'
    end

    # Canonicalization ignores map order only. Arrays and scalar types retain
    # their meaning; duplicate JSON or symbol/string-normalized keys fail closed.
    module Identity
      def self.canonical(value)
        case value
        when Hash
          normalized = {}
          value.each do |key, item|
            raise ContractError, 'Non-string JSON map key' unless key.is_a?(String) || key.is_a?(Symbol)
            raise ContractError, "Duplicate normalized key #{key}" if normalized.has_key?(key.to_s)

            normalized[key.to_s] = canonical(item)
          end
          normalized.sort.to_h
        when Array then value.map { |item| canonical(item) }
        when String, Integer, TrueClass, FalseClass, NilClass then value
        when Float
          raise ContractError, 'Non-finite JSON number' unless value.finite?

          value
        else raise ContractError, "Non-JSON value #{value.class}"
        end
      end

      def self.digest(value)
        Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
      end

      def self.json(response)
        body = parse(response.body)
        canonical = canonical(body)
        { http_status: response.status, envelope_status: body.fetch('status'),
          body_bytes: response.body.bytesize, body_sha256: Digest::SHA256.hexdigest(response.body),
          canonical_sha256: Digest::SHA256.hexdigest(JSON.generate(canonical)), canonical_body: canonical }
      end

      def self.parse(string)
        JSON.parse(string, allow_duplicate_key: false)
      rescue JSON::ParserError => e
        raise ContractError, "Duplicate key or invalid JSON: #{e.message}"
      end

      def self.key(spec)
        JSON.generate(canonical('id' => spec.fetch('id'), 'dimensions' => spec.fetch('dimensions')))
      end
    end

    class Comparator
      def initialize(samples, budgets, budget_sha256:)
        @samples = samples
        @budgets = budgets
        @budget_sha256 = budget_sha256
      end

      def compare
        validate_header
        inventory = @samples.fetch('inventory').map { |spec| Identity.key(spec) }
        cases = @samples.fetch('cases')
        budget_cases = @budgets.fetch('profiles').fetch(@samples.fetch('profile'))
        unless inventory.uniq == inventory && inventory.sort == cases.map { |item| Identity.key(item) }.sort &&
               inventory.sort == budget_cases.map { |item| Identity.key(item) }.sort
          raise ContractError, 'Missing, duplicate or unexpected workload'
        end

        results = cases.map do |item|
          budget = budget_cases.find { |entry| Identity.key(entry) == Identity.key(item) }
          compare_case(item, budget)
        end
        status = if results.any? { |item| item['classification'] == 'regression' }
                   'regression'
                 elsif results.any? { |item| item['classification'] == 'inconclusive' }
                   'inconclusive'
                 else
                   'pass'
                 end
        @samples.merge('status' => status, 'cases' => results)
      rescue KeyError, TypeError, NoMethodError, ArgumentError => e
        raise ContractError, "Invalid comparison input: #{e.message}"
      end

      private

      def validate_header
        raise ContractError, 'Unsupported schema' unless @samples.fetch('schema_version') == 1 && @budgets.fetch('schema_version') == 1
        raise ContractError, 'Wrong fixed reference' unless @budgets.fetch('reference_sha') == REFERENCE
        raise ContractError, 'Budget digest mismatch' unless @samples.fetch('budget_sha256') == @budget_sha256

        @policy = PROFILES.fetch(@samples.fetch('profile'))
        calibration = @budgets.fetch('calibration').fetch(@samples.fetch('profile'))
        unless calibration.fetch('source_sha') == REFERENCE && calibration.fetch('raw_sha256').match?(/\A[0-9a-f]{64}\z/) &&
               calibration.fetch('warmup_batches') == 2 && calibration.fetch('iterations').is_a?(Integer) && calibration['iterations'] > 0 &&
               !calibration.fetch('fixture_sha256').empty? && !calibration.fetch('inputs').empty?
          raise ContractError, 'Missing calibrated reference evidence'
        end

        %w[baseline_sha candidate_sha harness_sha256].each do |field|
          length = field.end_with?('_sha256') ? 64 : 40
          raise ContractError, "Missing #{field}" unless @samples.fetch(field).match?(/\A[0-9a-f]{#{length}}\z/)
        end
        Performance.validate_source_pair(profile: @samples.fetch('profile'), baseline_sha: @samples.fetch('baseline_sha'),
                                         candidate_sha: @samples.fetch('candidate_sha'))
        raise ContractError, 'Missing fixture provenance' if @samples.fetch('fixture_sha256').empty?
        raise ContractError, 'Missing source provenance' unless @samples.fetch('sources').keys.sort == %w[baseline candidate]
        raise ContractError, 'Missing environment' if @samples.fetch('environment').empty?
        unless @samples.fetch('environment') == @budgets.fetch('environment').fetch(@samples.fetch('profile'))
          raise ContractError, 'Calibration environment mismatch'
        end

        sources = @samples.fetch('sources')
        %w[baseline candidate].each do |role|
          source = sources.fetch(role)
          unless source.fetch('sha') == @samples.fetch("#{role}_sha") && source.fetch('root').start_with?('/') &&
                 source.fetch('tree').match?(/\A[0-9a-f]{40}\z/) && source.fetch('tracked_files').is_a?(Integer) && source['tracked_files'] > 0
            raise ContractError, 'Invalid source proof'
          end
        end
        observations = @samples.fetch('observations')
        raise ContractError, 'Missing worker provenance' if observations.empty?

        observations.each_value do |observation|
          source = observation.fetch('source')
          raise ContractError, 'Worker root/SHA absent from source proof' unless sources.values.any? { |entry| entry['root'] == source['root'] && entry['sha'] == source['sha'] }
          raise ContractError, 'Missing loaded sources' if source.fetch('loaded_sources').empty?
          raise ContractError, 'Runtime policy mismatch' unless observation.fetch('runtime_policy') == RUNTIME_POLICY
          raise ContractError, 'Missing host diagnostics' unless %w[hostname os cpu].all? { |key| observation.fetch('host').fetch(key).is_a?(String) }

          selected = sources.values.find { |entry| entry['root'] == source['root'] && entry['sha'] == source['sha'] }
          source.fetch('loaded_sources').each do |path, sha256|
            raise ContractError, 'Loaded runtime not in verified source tree' unless selected.fetch('files_sha256').fetch(path) == sha256
          end
          unless observation.fetch('environment') == @samples['environment'] && observation.fetch('inputs') == @samples.fetch('inputs') &&
                 observation.fetch('fixture_sha256') == @samples['fixture_sha256']
            raise ContractError, 'Worker provenance mismatch'
          end
        end
        return if @samples.fetch('inputs').fetch('locks').any? && @samples['inputs'].fetch('manifests').any?

        raise ContractError, 'Missing dependency graph'
      end

      def number(value)
        raise ContractError, 'Invalid nonnegative finite metric' unless value.is_a?(Numeric) && value.finite? && value >= 0

        value
      end

      def median(values)
        sorted = values.sort
        middle = sorted.length / 2
        sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
      end

      def validate_sample(sample, iterations, budget)
        METRICS.each { |metric| number(sample.fetch(metric)) }
        raise ContractError, 'Operation count mismatch' unless sample.fetch('operations') == iterations

        outputs = sample.fetch('outputs')
        records = sample.fetch('counters').fetch('operations')
        raise ContractError, 'Missing per-operation output/counter records' unless outputs.length == iterations && records.length == iterations

        proof = @samples.fetch('observations').fetch(sample.fetch('observation'))
        raise ContractError, 'Sample source provenance missing' unless proof

        bodies = sample.fetch('bodies')
        bodies.each do |digest, value|
          raise ContractError, 'Raw output digest mismatch' unless Digest::SHA256.hexdigest(value.fetch('body')) == digest
        end

        outputs.each do |output|
          raise ContractError, 'Invalid output status' unless output.fetch('http_status').is_a?(Integer)
          raise ContractError, 'Missing envelope status' unless output.has_key?('envelope_status')
          raise ContractError, 'Empty output' unless number(output.fetch('body_bytes')) > 0

          %w[body_sha256 canonical_sha256].each do |field|
            raise ContractError, "Missing #{field}" unless output.fetch(field).match?(/\A[0-9a-f]{64}\z/)
          end
          raw = bodies.fetch(output['body_sha256'])
          raise ContractError, 'Raw body byte count mismatch' unless raw.fetch('body').bytesize == output['body_bytes']

          canonical = raw['canonical_body']
          digest = canonical.nil? ? output['body_sha256'] : Identity.digest(canonical)
          if digest != output['canonical_sha256']
            raise ContractError, 'Canonical output digest mismatch'
          end
          if !canonical.nil? && Identity.digest(Identity.parse(raw['body'])) != output['canonical_sha256']
            raise ContractError, 'Raw/canonical output values differ'
          end
        end
        expected = budget.fetch('counters')
        raise ContractError, 'Uncalibrated counter budget' unless (COUNTERS - expected.keys).empty?
        unless expected.values.all? { |value| value.is_a?(Integer) && value >= 0 }
          raise ContractError, 'Invalid calibrated counter budget'
        end

        records.each do |record|
          raise ContractError, 'Counter keys mismatch' unless record.keys.sort == expected.keys.sort

          record.each do |key, value|
            raise ContractError, 'Invalid counter' unless value.is_a?(Integer) && value >= 0
            raise ContractError, "Counter contract #{key}: #{value}, expected #{expected[key]}" unless value == expected[key]
          end
        end
      end

      def same_outputs(left, right)
        left.zip(right).all? do |a, b|
          %w[http_status envelope_status canonical_sha256].all? { |field| a[field] == b[field] }
        end
      end

      def compare_case(item, budget)
        iterations = item.fetch('iterations')
        raise ContractError, 'Invalid batch size' unless iterations.is_a?(Integer) && iterations.between?(1, 2000)

        self_pairs = item.fetch('self_pairs')
        pairs = item.fetch('pairs')
        raise ContractError, 'Incomplete pair inventory' unless self_pairs.length == @policy[:self_pairs] && pairs.length == @policy[:pairs]

        reference = number(budget.fetch('reference_allocations'))
        ceiling = number(budget.fetch('allocation_ceiling'))
        raise ContractError, 'Uncalibrated allocation ceiling' unless reference > 0 && ceiling == (reference * 1.25).ceil + 32

        canonical_outputs = nil
        (self_pairs + pairs).each_with_index do |pair, index|
          expected_order = if index < self_pairs.length
                             %w[baseline baseline]
                           elsif (index - self_pairs.length).even?
                             %w[baseline candidate]
                           else
                             %w[candidate baseline]
                           end
          raise ContractError, 'Wrong comparison order' unless pair.fetch('order') == expected_order

          pair_index = index < self_pairs.length ? index : index - self_pairs.length
          expected_workload_order = pair_index.even? ? 'forward' : 'reverse'
          raise ContractError, 'Wrong workload order' unless pair.fetch('workload_order') == expected_workload_order

          %w[baseline candidate].each do |role|
            sample = pair.fetch(role)
            validate_sample(sample, iterations, budget)
            expected_sha = index < self_pairs.length ? @samples['baseline_sha'] : @samples["#{role}_sha"]
            actual_sha = @samples['observations'].fetch(sample['observation']).fetch('source').fetch('sha')
            raise ContractError, 'Sample belongs to wrong revision' unless actual_sha == expected_sha
            if @samples['observations'].fetch(sample['observation']).fetch('workload_order') != expected_workload_order
              raise ContractError, 'Worker workload order mismatch'
            end

            canonical_outputs ||= sample.fetch('outputs')
            raise ContractError, 'Response identity differs between operations/revisions' unless same_outputs(canonical_outputs, sample['outputs'])
          end
        end
        classifications = %w[wall_seconds cpu_seconds].to_h do |metric|
          baseline = pairs.map { |pair| pair['baseline'][metric] }
          noise = [self_pairs.map { |pair| (pair['baseline'][metric] - pair['candidate'][metric]).abs }.max,
                   0.05 * median(baseline), 0.00005].max
          excess = pairs.map do |pair|
            b = pair['baseline'][metric]
            pair['candidate'][metric] - b - [0.20 * b, 0.00020].max
          end
          failed = excess.count { |value| value > noise }
          passed = excess.count { |value| value < -noise }
          classification = if failed >= @policy[:agreement] then 'regression'
                           elsif passed >= @policy[:agreement] then 'pass'
                           else 'inconclusive'
                           end
          [metric, { 'classification' => classification, 'noise' => noise,
                     'excess' => excess, 'regression_agreement' => failed, 'pass_agreement' => passed }]
        end
        base_allocations = median(pairs.map { |pair| pair['baseline']['allocated_objects'] })
        candidate_allocations = median(pairs.map { |pair| pair['candidate']['allocated_objects'] })
        allocations_failed = candidate_allocations > base_allocations + [0.10 * base_allocations, 32].max || candidate_allocations > ceiling
        classification = if allocations_failed || classifications.values.any? { |result| result['classification'] == 'regression' }
                           'regression'
                         elsif classifications.values.any? { |result| result['classification'] == 'inconclusive' }
                           'inconclusive'
                         else
                           'pass'
                         end
        item.merge('classification' => classification, 'timing' => classifications,
                   'allocations' => { 'baseline_median' => base_allocations, 'candidate_median' => candidate_allocations,
                                      'reference_ceiling' => ceiling, 'classification' => allocations_failed ? 'regression' : 'pass' })
      end
    end
  end
end
