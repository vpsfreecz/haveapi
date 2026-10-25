require 'json'
require 'open3'
require 'tmpdir'
require 'yaml'
require_relative '../../../../utils/performance_ci'

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
    allow(repository).to receive_messages(ancestor?: true, paths: ['servers/ruby/lib/haveapi/server.rb'])
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

  it 'compares an entire default-branch push batch against event before' do
    event.merge!('ref' => 'refs/heads/master', 'after' => candidate, 'before' => base)
    allow(repository).to receive(:merge_base)

    expect(resolve('push', event)).to include(baseline_sha: base, candidate_sha: candidate)
    expect(repository).not_to have_received(:merge_base)
  end

  [false, true].each do |new_branch|
    it "uses the whole feature merge-base for a #{new_branch ? 'new' : 'subsequent'} push" do
      event.merge!('ref' => 'refs/heads/feature', 'after' => candidate,
                   'before' => new_branch ? '0' * 40 : sha('a'), 'created' => new_branch)
      allow(repository).to receive(:merge_base).with(candidate, default).and_return(base)

      expect(resolve('push', event, default_sha: default)).to include(baseline_sha: base, captured_default_sha: default)
    end
  end

  it 'rejects initial default-branch pushes without an available predecessor' do
    event.merge!('ref' => 'refs/heads/master', 'after' => candidate, 'before' => '0' * 40)
    expect { resolve('push', event) }.to raise_error(described_class::Error)
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
    allow(repository).to receive(:paths).and_return(['clients/php/README.md'])
    event.merge!('ref' => 'refs/heads/master', 'after' => candidate, 'before' => base)
    expect(resolve('push', event)).to include(relevant: false)
    expect(resolve('schedule', event)).to include(relevant: true)
    expect(resolve('workflow_dispatch', event)).to include(relevant: true)
  end

  it 'detects configuration, dependencies, harness and workflow changes' do
    %w[flake.lock Gemfile Makefile .ruby-version servers/ruby/benchmarks/endpoints.rb
       servers/ruby/test_support/performance_sqlite_fixture.rb clients/ruby/Gemfile clients/rust/Gemfile
       doc/performance.md utils/performance_ci.rb .github/workflows/servers-ruby-performance.yml].each do |path|
      expect(described_class::RELEVANT).to match(path)
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

  [0, 1, 2, 3].each do |code|
    it "preserves actual runner exit #{code} with a matching report" do
      Dir.mktmpdir('haveapi-runner-wrapper-') do |directory|
        checkout = File.join(directory, 'checkout')
        FileUtils.mkdir_p(File.join(checkout, 'servers/ruby/benchmarks'))
        script = <<~RUBY
          require 'json'
          require 'fileutils'
          output = ARGV.fetch(ARGV.index('--output') + 1)
          FileUtils.mkdir_p(output)
          File.write(File.join(output, 'report.json'), JSON.generate(
            schema_version: 1, status: '#{{ 0 => 'pass', 1 => 'regression', 2 => 'inconclusive', 3 => 'error' }.fetch(code)}',
            baseline_sha: '#{base}', candidate_sha: '#{candidate}'
          ))
          exit #{code}
        RUBY
        File.write(File.join(checkout, 'servers/ruby/benchmarks/endpoints.rb'), script)
        allow(repository).to receive(:root).and_return(checkout)
        allow(repository).to receive(:git).with('rev-parse', 'HEAD').and_return(candidate)
        allow(repository).to receive(:git).with('diff', 'HEAD', '--').and_return('')
        selection = { 'schema_version' => 1, 'relevant' => true, 'profile' => 'quick',
                      'baseline_sha' => base, 'candidate_sha' => candidate }
        campaign = described_class::Campaign.new(repository:, selection:,
                                                 evidence: File.join(directory, 'evidence'), sources: File.join(directory, 'sources'))
        allow(campaign).to receive(:export).with(:baseline, base).and_return(directory)
        allow(campaign).to receive(:export).with(:candidate, candidate).and_return(directory)
        allow(campaign).to receive_messages(verify_dependencies: nil, retain_inputs: nil, command!: nil)
        expect(campaign.run).to eq(code)
        expect(File.read(File.join(directory, 'evidence/runner.exit')).strip).to eq(code.to_s)
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
    expect(job.fetch('timeout-minutes')).to include('30', '10')
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
