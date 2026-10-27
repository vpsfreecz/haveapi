require 'json'
require 'open3'
require 'tmpdir'
require 'yaml'
require_relative '../../../../utils/performance_ci'
require_relative 'support/samples'

RSpec.describe HaveAPI::PerformanceCI do
  let(:candidate) { sha('c') }
  let(:default) { sha('d') }
  let(:base) { sha('b') }
  let(:event) { { 'repository' => { 'default_branch' => 'master' } } }
  let(:repository) { instance_double(described_class::Repository) }

  def sha(character)
    character * 40
  end

  def resolver
    described_class::Resolver.new(repository)
  end

  before do
    allow(repository).to receive(:default_sha).with('master').and_return(default)
    allow(repository).to receive(:commit!) do |value|
      unless value.is_a?(String) && described_class::SHA.match?(value) && value != '0' * 40
        raise described_class::Error, 'invalid commit'
      end

      value
    end
    allow(repository).to receive_messages(ancestor?: true, paths: ['servers/ruby/lib/haveapi/server.rb'], release_lineage: nil)
  end

  def resolve(name, data, **options)
    resolver.resolve(event_name: name, event: data, event_sha: candidate, **options)
  end

  it 'selects the PR event head instead of its synthetic merge commit' do
    event['pull_request'] = { 'head' => { 'sha' => candidate }, 'base' => { 'sha' => default } }
    allow(repository).to receive(:merge_base).with(candidate, default).and_return(base)

    result = resolver.resolve(event_name: 'pull_request', event:, event_sha: sha('e'))
    expect(result).to include(candidate_sha: candidate, baseline_sha: base, profile: 'quick', relevant: true)
  end

  %w[master feature].each do |branch|
    it "compares the exact #{branch} push batch against event before" do
      event.merge!('ref' => "refs/heads/#{branch}", 'after' => candidate, 'before' => base)
      allow(repository).to receive(:merge_base)

      expect(resolve('push', event)).to include(baseline_sha: base, candidate_sha: candidate,
                                                reason: 'push event before/after batch',
                                                push_pair: { 'event_name' => 'push', 'before' => base, 'after' => candidate })
      expect(repository).to have_received(:paths).with(base, candidate)
      expect(repository).not_to have_received(:merge_base)
    end

    it "permits a nonancestor #{branch} rewrite only for the exact pushed pair" do
      event.merge!('ref' => "refs/heads/#{branch}", 'after' => candidate, 'before' => base, 'forced' => true)
      allow(repository).to receive(:ancestor?).with(base, candidate).and_return(false)
      allow(repository).to receive(:merge_base)

      result = resolver.resolve(event_name: 'push', event:, event_sha: sha('e'))
      expect(result).to include(baseline_sha: base, candidate_sha: candidate,
                                push_pair: { 'event_name' => 'push', 'before' => base, 'after' => candidate })
      expect(repository).to have_received(:paths).with(base, candidate)
      expect(repository).not_to have_received(:merge_base)
    end
  end

  [false, true].each do |created|
    it "uses the captured default merge-base for a zero-before push with created=#{created}" do
      event.merge!('ref' => 'refs/heads/feature', 'after' => candidate,
                   'before' => '0' * 40, 'created' => created)
      allow(repository).to receive(:merge_base).with(candidate, default).and_return(base)

      result = resolve('push', event, default_sha: default)
      expect(result).to include(baseline_sha: base, captured_default_sha: default,
                                reason: 'new-branch merge-base against captured default')
      expect(result[:push_pair]).to be_nil
      expect(repository).to have_received(:paths).with(base, candidate)
    end
  end

  it 'does not guess a fallback when the captured default commit is unavailable' do
    event.merge!('ref' => 'refs/heads/feature', 'after' => candidate, 'before' => '0' * 40)
    allow(repository).to receive(:commit!).with(default).and_raise(described_class::Error, 'unavailable default')
    expect { resolve('push', event, default_sha: default) }.to raise_error(described_class::Error, /unavailable default/)
  end

  it 'rejects a new branch whose captured-default merge-base equals its head' do
    event.merge!('ref' => 'refs/heads/master', 'after' => candidate, 'before' => '0' * 40)
    allow(repository).to receive(:merge_base).with(candidate, default).and_return(candidate)
    expect { resolve('push', event) }.to raise_error(described_class::Error, /differ/)
  end

  it 'does not replace an unavailable new-branch merge-base with another commit' do
    event.merge!('ref' => 'refs/heads/feature', 'after' => candidate, 'before' => '0' * 40)
    allow(repository).to receive(:merge_base).with(candidate, default).and_raise(described_class::Error, 'no merge-base')
    expect { resolve('push', event) }.to raise_error(described_class::Error, /no merge-base/)
  end

  it 'requires ancestry for the new-branch fallback instead of granting a push-pair exception' do
    event.merge!('ref' => 'refs/heads/feature', 'after' => candidate, 'before' => '0' * 40)
    allow(repository).to receive(:merge_base).with(candidate, default).and_return(base)
    allow(repository).to receive(:ancestor?).with(base, candidate).and_return(false)
    expect { resolve('push', event) }.to raise_error(described_class::Error, /ancestor/)
  end

  it 'does not grant the quick push exception to a weekly push profile' do
    event.merge!('ref' => 'refs/heads/feature', 'after' => candidate, 'before' => described_class::REFERENCE,
                 'inputs' => { 'profile' => 'weekly' })
    allow(repository).to receive(:ancestor?).with(described_class::REFERENCE, candidate).and_return(false)
    expect { resolve('push', event) }.to raise_error(described_class::Error, /ancestor/)
  end

  %w[before after].each do |endpoint|
    [nil, '', 'short', 'A' * 40].each do |invalid|
      it "rejects an invalid push #{endpoint} #{invalid.inspect}" do
        event.merge!('ref' => 'refs/heads/feature', 'before' => base, 'after' => candidate, endpoint => invalid)
        expect { resolve('push', event) }.to raise_error(described_class::Error)
        expect(repository).not_to have_received(:paths)
      end
    end

    it "rejects a missing push #{endpoint}" do
      event.merge!('ref' => 'refs/heads/feature', 'before' => base, 'after' => candidate)
      event.delete(endpoint)
      expect { resolve('push', event) }.to raise_error(described_class::Error)
      expect(repository).not_to have_received(:paths)
    end

    %w[noncommit unavailable].each do |failure|
      it "rejects a #{failure} push #{endpoint} without substituting a merge-base" do
        event.merge!('ref' => 'refs/heads/feature', 'before' => base, 'after' => candidate)
        allow(repository).to receive(:commit!).with(event.fetch(endpoint)).and_raise(described_class::Error, failure)
        allow(repository).to receive(:merge_base)
        expect { resolve('push', event) }.to raise_error(described_class::Error, failure)
        expect(repository).not_to have_received(:merge_base)
        expect(repository).not_to have_received(:paths)
      end
    end
  end

  it 'rejects zero after and equal push endpoints' do
    event.merge!('ref' => 'refs/heads/feature', 'before' => base, 'after' => '0' * 40)
    expect { resolve('push', event) }.to raise_error(described_class::Error)
    event['after'] = base
    expect { resolve('push', event) }.to raise_error(described_class::Error, /differ/)
    expect(repository).not_to have_received(:paths)
  end

  context 'with the verified maintenance lineage' do
    def release
      sha('e')
    end

    def lineage
      { 'candidate_sha' => candidate, 'mapped_sha' => HaveAPI::Performance::Release::MAPPED }
    end

    before do
      allow(repository).to receive(:release_lineage).with(candidate).and_return(lineage)
      allow(repository).to receive(:default_sha).with('haveapi-0.30').and_return(release)
    end

    it 'compares the complete maintenance push batch using event before' do
      event.merge!('ref' => 'refs/heads/haveapi-0.30', 'before' => base, 'after' => candidate)
      expect(resolve('push', event)).to include(baseline_sha: base, candidate_sha: candidate,
                                                release_lineage: lineage, reason: 'push event before/after batch',
                                                push_pair: { 'event_name' => 'push', 'before' => base, 'after' => candidate })
    end

    it 'permits a proven maintenance rewrite with the exact push pair' do
      event.merge!('ref' => 'refs/heads/haveapi-0.30', 'before' => base, 'after' => candidate, 'forced' => true)
      allow(repository).to receive(:ancestor?).with(base, candidate).and_return(false)
      expect(resolve('push', event)).to include(baseline_sha: base, candidate_sha: candidate, release_lineage: lineage,
                                                push_pair: { 'event_name' => 'push', 'before' => base, 'after' => candidate })
    end

    it 'uses exact before for an existing maintenance feature without looking up a release head' do
      event.merge!('ref' => 'refs/heads/feature', 'before' => base, 'after' => candidate)
      expect(resolve('push', event)).to include(baseline_sha: base, candidate_sha: candidate, release_lineage: lineage)
      expect(repository).not_to have_received(:default_sha).with('haveapi-0.30')
    end

    it 'uses the captured default merge-base for a new maintenance feature' do
      event.merge!('ref' => 'refs/heads/feature', 'before' => '0' * 40, 'after' => candidate)
      allow(repository).to receive(:merge_base).with(candidate, default).and_return(base)
      expect(resolve('push', event)).to include(baseline_sha: base, captured_default_sha: default, release_lineage: lineage)
      expect(repository).not_to have_received(:default_sha).with('haveapi-0.30')
    end

    it 'accepts only the original weekly reference through the proven mapping' do
      event['inputs'] = { 'profile' => 'weekly', 'candidate_sha' => candidate, 'baseline_sha' => described_class::REFERENCE }
      allow(repository).to receive(:ancestor?).with(described_class::REFERENCE, candidate).and_return(false)
      expect(resolve('workflow_dispatch', event)).to include(baseline_sha: described_class::REFERENCE, release_lineage: lineage)
      event['inputs']['profile'] = 'quick'
      expect { resolve('workflow_dispatch', event) }.to raise_error(described_class::Error, /ancestor/)
      event['inputs']['profile'] = 'weekly'
      allow(repository).to receive(:release_lineage).with(candidate).and_return(nil)
      expect { resolve('workflow_dispatch', event) }.to raise_error(described_class::Error, /ancestor/)
    end

    it 'does not accept an unrelated explicit quick baseline' do
      event['inputs'] = { 'candidate_sha' => candidate, 'baseline_sha' => base }
      allow(repository).to receive(:ancestor?).with(base, candidate).and_return(false)
      expect { resolve('workflow_dispatch', event) }.to raise_error(described_class::Error, /ancestor/)
    end
  end

  it 'rejects unproven maintenance branch history' do
    event.merge!('ref' => 'refs/heads/haveapi-0.30', 'before' => base, 'after' => candidate)
    expect { resolve('push', event) }.to raise_error(described_class::Error, /Unproven/)
  end

  it 'rejects deleted pushes and tag events' do
    expect { resolve('push', event.merge('deleted' => true)) }.to raise_error(described_class::Error, /Deleted/)
    expect { resolve('push', event.merge('ref' => 'refs/tags/v1')) }.to raise_error(described_class::Error, /branch/)
  end

  it 'requires a real ancestor and never substitutes a same-head baseline' do
    event['inputs'] = { 'candidate_sha' => candidate, 'baseline_sha' => base }
    allow(repository).to receive(:ancestor?).with(base, candidate).and_return(false)
    expect { resolve('workflow_dispatch', event) }.to raise_error(described_class::Error, /ancestor/)
    event['inputs']['baseline_sha'] = candidate
    expect { resolve('workflow_dispatch', event) }.to raise_error(described_class::Error, /differ/)
  end

  it 'does not extend the push exception to pull requests or schedules' do
    event['pull_request'] = { 'head' => { 'sha' => candidate }, 'base' => { 'sha' => default } }
    allow(repository).to receive(:merge_base).with(candidate, default).and_return(base)
    allow(repository).to receive(:ancestor?).with(base, candidate).and_return(false)
    expect { resolve('pull_request', event) }.to raise_error(described_class::Error, /ancestor/)
    allow(repository).to receive(:ancestor?).with(described_class::REFERENCE, candidate).and_return(false)
    expect { resolve('schedule', event) }.to raise_error(described_class::Error, /ancestor/)
  end

  it 'uses the exact scheduled event SHA and preserves fixed reference ancestry' do
    expect(resolve('schedule', event)).to include(candidate_sha: candidate, baseline_sha: described_class::REFERENCE, profile: 'weekly')
    expect(repository).to have_received(:ancestor?).with(described_class::REFERENCE, candidate)
  end

  it 'defaults manual runs to captured default and fixed reference' do
    expect(resolve('workflow_dispatch', event)).to include(candidate_sha: default, baseline_sha: described_class::REFERENCE)
  end

  it 'accepts complete explicit manual SHA pairs and weekly profile' do
    event['inputs'] = { 'candidate_sha' => candidate, 'baseline_sha' => described_class::REFERENCE, 'profile' => 'weekly' }
    expect(resolve('workflow_dispatch', event)).to include(candidate_sha: candidate, baseline_sha: described_class::REFERENCE, profile: 'weekly')
    event['inputs']['baseline_sha'] = base
    expect { resolve('workflow_dispatch', event) }.to raise_error(described_class::Error, /fixed/)
  end

  it 'rejects partial manual pairs, invalid profiles and missing event data' do
    event['inputs'] = { 'candidate_sha' => candidate }
    expect { resolve('workflow_dispatch', event) }.to raise_error(described_class::Error)
    event['inputs'] = { 'profile' => 'unbounded' }
    expect { resolve('workflow_dispatch', event) }.to raise_error(described_class::Error, /profile/)
    expect { resolve('pull_request', {}) }.to raise_error(described_class::Error, /Incomplete/)
    expect { resolve('pull_request_target', event.merge('inputs' => {})) }.to raise_error(described_class::Error, /Unsupported/)
  end

  it 'does not hide unavailable commits behind a no-path success' do
    event['inputs'] = { 'candidate_sha' => candidate, 'baseline_sha' => base }
    allow(repository).to receive(:commit!).with(base).and_raise(described_class::Error, 'unavailable')
    expect { resolve('workflow_dispatch', event) }.to raise_error(described_class::Error, 'unavailable')
  end

  it 'skips only irrelevant valid push/PR changes and still forces scheduled/manual work' do
    allow(repository).to receive(:paths).and_return(['LICENSE.txt'])
    event.merge!('ref' => 'refs/heads/master', 'after' => candidate, 'before' => base)
    expect(resolve('push', event)).to include(relevant: false)
    expect(resolve('schedule', event)).to include(relevant: true)
    expect(resolve('workflow_dispatch', event)).to include(relevant: true)
  end

  it 'detects configuration, dependencies, harness and workflow changes' do
    %w[flake.lock Gemfile Makefile .ruby-version servers/ruby/benchmarks/endpoints.rb
       servers/ruby/benchmarks/Gemfile servers/ruby/benchmarks/Gemfile.lock servers/ruby/benchmarks/shell.nix
       servers/ruby/test_support/performance_sqlite_fixture.rb clients/ruby/Gemfile clients/rust/Gemfile
       doc/performance.md utils/performance_ci.rb .github/workflows/servers-ruby-performance.yml
       servers/ruby/benchmarks/spec/client_examples_spec.rb servers/ruby/test_support/all_client_performance_fixture.rb
       clients/go/lib/haveapi/go_client/documentation.rb clients/typescript/lib/haveapi/typescript_client/documentation.rb
       clients/js/src/client.ts clients/python/haveapi/client.py clients/php/src/Client.php clients/new-client/renderer.rb].each do |path|
      expect(described_class::RELEVANT).to match(path)
    end
  end

  it 'requires the current-client contract before comparison and rejects a missing contract outcome' do
    path = File.expand_path('../../../../.github/workflows/servers-ruby-performance.yml', __dir__)
    steps = YAML.load_file(path).fetch('jobs').fetch('performance').fetch('steps')
    contract = steps.find { |step| step['id'] == 'clients' }
    comparison = steps.find { |step| step['name'] == 'Run the selected pair outside Bundler' }
    expect(steps.index(contract)).to be < steps.index(comparison)
    expect(contract.fetch('if')).to eq(comparison.fetch('if'))
    expect(contract.fetch('run')).to include('make test-performance-clients', "echo 'outcome=passed'")
    completion = steps.find { |step| step['id'] == 'completion' }
    Dir.mktmpdir('haveapi-client-contract-gate-') do |directory|
      File.write(File.join(directory, 'selection.json'), '{}')
      File.write(File.join(directory, 'runner.exit'), "0\n")
      FileUtils.mkdir_p(File.join(directory, 'results'))
      File.write(File.join(directory, 'results/report.json'), '{}')
      File.write(File.join(directory, 'all-client-contract.log'), 'passed')
      [nil, '', 'failed', 'passed'].each do |outcome|
        environment = { 'RELEVANT' => 'true', 'CLIENT_CONTRACT' => outcome,
                        'PERFORMANCE_EVIDENCE' => directory, 'GITHUB_OUTPUT' => File.join(directory, 'output') }
        _output, _error, status = Open3.capture3(environment, 'bash', '-euo', 'pipefail', '-c', completion.fetch('run'))
        expect(status.success?).to eq(outcome == 'passed')
      end
    end
  end

  it 'only accepts successful job completion in the aggregate gate' do
    expect(described_class.aggregate!('success', 'compared')).to be(true)
    expect(described_class.aggregate!('success', 'no-work')).to be(true)
    %w[failure cancelled skipped unknown].each do |result|
      expect { described_class.aggregate!(result, 'compared') }.to raise_error(described_class::Error)
    end
    [nil, '', 'unknown'].each do |outcome|
      expect { described_class.aggregate!('success', outcome) }.to raise_error(described_class::Error)
    end
  end

  it 'fails aggregate shell execution for missing outcomes and cancelled or skipped work' do
    path = File.expand_path('../../../../.github/workflows/servers-ruby-performance.yml', __dir__)
    script = YAML.load_file(path).fetch('jobs').fetch('gate').fetch('steps').first.fetch('run')
    [['success', 'compared', true], ['success', 'no-work', true], ['success', '', false],
     ['failure', 'compared', false], ['cancelled', 'compared', false], ['skipped', 'no-work', false]].each do |result, outcome, accepted|
      _output, _error, status = Open3.capture3({ 'PERFORMANCE_RESULT' => result, 'PERFORMANCE_OUTCOME' => outcome },
                                               'bash', '-e', '-c', script)
      expect(status.success?).to eq(accepted), "#{result}/#{outcome}"
    end
  end

  [[0, 'pass', false], [0, 'inconclusive', false], [1, 'regression', false], [3, 'error', false], [0, 'pass', true]].each do |code, outcome, rewrite|
    it "preserves actual runner exit #{code}/#{outcome} and writes its summary#{' for a nonancestor push' if rewrite}" do
      Dir.mktmpdir('haveapi-runner-wrapper-') do |directory|
        checkout = File.join(directory, 'checkout')
        FileUtils.mkdir_p(File.join(checkout, 'servers/ruby/benchmarks'))
        samples, budget_json = PerformanceSamples.fixture
        report = HaveAPI::Performance::Comparator.new(samples, JSON.parse(budget_json), budget_sha256: samples['budget_sha256']).compare
        report.merge!('status' => outcome, 'baseline_sha' => base, 'candidate_sha' => candidate)
        item = report['cases'].first
        item['classification'] = outcome
        item['timing']['wall_seconds']['classification'] = outcome
        item['responses']['raw_changed'] = true
        item['responses']['bytes_per_request'].merge!('baseline' => 100.0, 'candidate' => 112.0, 'delta' => 12.0, 'delta_percent' => 12.0)
        summary_path = File.join(directory, 'summary.md')
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:[]).with('GITHUB_STEP_SUMMARY').and_return(summary_path)
        allow(ENV).to receive(:fetch).with('GITHUB_STEP_SUMMARY').and_return(summary_path)
        script = <<~RUBY
          require 'json'
          require 'fileutils'
          output = ARGV.fetch(ARGV.index('--output') + 1)
          FileUtils.mkdir_p(output)
          File.write(File.join(output, 'report.json'), #{JSON.generate(report).dump})
          exit #{code}
        RUBY
        File.write(File.join(checkout, 'servers/ruby/benchmarks/endpoints.rb'), script)
        allow(repository).to receive(:root).and_return(checkout)
        allow(repository).to receive(:git).with('rev-parse', 'HEAD').and_return(candidate)
        allow(repository).to receive(:git).with('diff', 'HEAD', '--').and_return('')
        selection = { 'schema_version' => 1, 'relevant' => true, 'profile' => 'quick',
                      'baseline_sha' => base, 'candidate_sha' => candidate }
        if rewrite
          selection.merge!('event_name' => 'push', 'push_pair' => { 'event_name' => 'push', 'before' => base, 'after' => candidate })
          allow(repository).to receive(:ancestor?).with(base, candidate).and_return(false)
        end
        campaign = described_class::Campaign.new(repository:, selection:,
                                                 evidence: File.join(directory, 'evidence'), sources: File.join(directory, 'sources'))
        allow(campaign).to receive(:export).with(:baseline, base).and_return(directory)
        allow(campaign).to receive(:export).with(:candidate, candidate).and_return(directory)
        allow(campaign).to receive_messages(verify_dependencies: nil, retain_inputs: nil, command!: nil)
        expect(campaign.run).to eq(code)
        expect(File.read(File.join(directory, 'evidence/runner.exit')).strip).to eq(code.to_s)
        summary = File.read(summary_path)
        expect(summary).to include("Performance comparison: #{outcome}", base, candidate)
        if outcome == 'error'
          expect(summary).not_to include('Bytes/request')
        else
          expect(summary).to include("| api.public_get {} | #{outcome} | #{outcome} | pass | pass | true | false | 100.00 → 112.00 | +12.00 (+12.00%) |")
        end
        if rewrite
          push_event = File.join(directory, 'evidence/push-event.json')
          expect(JSON.parse(File.read(push_event))).to eq(selection)
          command = JSON.parse(File.read(File.join(directory, 'evidence/runner-command.json')))
          expect(command.last(2)).to eq(['--push-event', push_event])
        end
      end
    end
  end

  it 'returns error exit 3 from the actual resolver CLI on incomplete input' do
    Dir.mktmpdir('haveapi-event-spec-') do |directory|
      file = File.join(directory, 'event.json')
      File.write(file, '{}')
      script = File.expand_path('../../../../utils/performance_ci.rb', __dir__)
      _output, error, status = Open3.capture3(RbConfig.ruby, script, 'resolve', '--event', file,
                                              '--event-name', 'pull_request', '--event-sha', candidate,
                                              '--repository', File.expand_path('../../../..', __dir__),
                                              '--output', File.join(directory, 'selection.json'))
      expect(status.exitstatus).to eq(3)
      expect(error).to include('Incomplete event')
      expect(File).not_to exist(File.join(directory, 'selection.json'))
    end
  end

  it 'keeps the hosted workflow always-created, read-only and bounded' do
    path = File.expand_path('../../../../.github/workflows/servers-ruby-performance.yml', __dir__)
    workflow = YAML.load_file(path)
    triggers = workflow.fetch('on') { workflow.fetch(true) }
    expect(triggers.keys).to contain_exactly('push', 'pull_request', 'schedule', 'workflow_dispatch')
    expect(triggers.fetch('push')).not_to have_key('paths')
    expect(triggers.fetch('pull_request')).to be_nil
    expect(triggers.fetch('schedule')).to eq([{ 'cron' => '0 3 * * 0' }])
    expect(workflow.fetch('permissions')).to eq('contents' => 'read')
    job = workflow.fetch('jobs').fetch('performance')
    expect(job.fetch('runs-on')).to eq('ubuntu-24.04')
    expect(job.fetch('timeout-minutes')).to include('45', '15')
    gate = workflow.fetch('jobs').fetch('gate')
    expect(gate).to include('name' => 'Performance gate', 'needs' => 'performance', 'if' => 'always()')
    expect(gate.fetch('steps').first.fetch('run')).to include('test "$PERFORMANCE_RESULT" = success')
    upload = job.fetch('steps').find { |step| step.fetch('uses', '').start_with?('actions/upload-artifact@') }
    expect(upload).to include('if' => 'always()')
    expect(upload.fetch('with')).to include('retention-days' => 30, 'if-no-files-found' => 'error')
    job.fetch('steps').select { |step| step.fetch('uses', '').start_with?('actions/checkout@') }.each do |step|
      expect(step.fetch('with')).to include('persist-credentials' => false, 'fetch-depth' => 0)
    end
  end
end
