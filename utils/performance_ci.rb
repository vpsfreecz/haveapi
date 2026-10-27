require_relative '../servers/ruby/benchmarks/performance_compare'
require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'optparse'
require 'rbconfig'

module HaveAPI
  module PerformanceCI
    REFERENCE = 'b85ec364057f536940d689b09e612512ffffaf82'.freeze
    SHA = /\A[0-9a-f]{40}\z/
    RELEVANT = %r{\A(?:servers/ruby/|clients/ruby/|clients/rust/|doc/|utils/performance_ci\.rb\z|utils/copydoc\.sh\z|\.github/workflows/servers-ruby-performance\.yml\z|(?:VERSION|Gemfile|Makefile|flake\.nix|flake\.lock|\.ruby-version)\z)}

    class Error < StandardError; end

    class Repository
      attr_reader :root

      def initialize(root)
        @root = File.realpath(root)
      end

      def git(*)
        output, error, status = Open3.capture3('git', '-C', root, *)
        raise Error, "Git failed: #{error.strip}" unless status.success?

        output
      end

      def commit!(sha)
        unless sha.is_a?(String) && SHA.match?(sha) && sha != '0' * 40
          raise Error, 'A nonzero full lowercase commit SHA is required'
        end
        raise Error, "Commit is unavailable: #{sha}" unless git('rev-parse', '--verify', "#{sha}^{commit}").strip == sha

        sha
      end

      def merge_base(left, right)
        commit!(git('merge-base', left, right).strip)
      end

      def ancestor?(left, right)
        _output, error, status = Open3.capture3('git', '-C', root, 'merge-base', '--is-ancestor', left, right)
        raise Error, "Cannot establish ancestry: #{error.strip}" unless [0, 1].include?(status.exitstatus)

        status.success?
      end

      def paths(left, right)
        git('diff', '--name-only', '-z', '--no-renames', left, right, '--').split("\0")
      end

      def default_sha(branch)
        commit!(git('rev-parse', '--verify', "refs/remotes/origin/#{branch}^{commit}").strip)
      end

      def release_lineage(candidate)
        Performance::Release.lineage(git: method(:git), ancestor: method(:ancestor?), candidate:)
      rescue Performance::ContractError => e
        raise Error, e.message
      end
    end

    class Resolver
      def initialize(repository)
        @repository = repository
      end

      def resolve(event_name:, event:, event_sha:, default_sha: nil)
        branch = event.fetch('repository').fetch('default_branch')
        raise Error, 'Missing repository default branch' unless branch.is_a?(String) && !branch.empty?

        profile = event_name == 'schedule' ? 'weekly' : event.fetch('inputs', {}).fetch('profile', 'quick')
        raise Error, 'Unknown performance profile' unless %w[quick weekly].include?(profile)

        default_sha ||= @repository.default_sha(branch)
        default_sha = @repository.commit!(default_sha)
        case event_name
        when 'pull_request'
          candidate = @repository.commit!(event.fetch('pull_request').fetch('head').fetch('sha'))
          anchor = @repository.commit!(event.fetch('pull_request').fetch('base').fetch('sha'))
          baseline = @repository.merge_base(candidate, anchor)
          reason = 'pull-request merge-base of exact head and event base'
        when 'push'
          raise Error, 'Deleted branch cannot be compared' if event['deleted']
          raise Error, 'Only branch pushes are supported' unless event.fetch('ref').start_with?('refs/heads/')

          candidate = @repository.commit!(event.fetch('after'))
          lineage = @repository.release_lineage(candidate)
          raise Error, 'Unproven maintenance lineage' if event.fetch('ref') == 'refs/heads/haveapi-0.30' && !lineage

          if event.fetch('before') == '0' * 40
            baseline = @repository.merge_base(candidate, default_sha)
            reason = 'new-branch merge-base against captured default'
          else
            baseline = @repository.commit!(event.fetch('before'))
            reason = 'push event before/after batch'
            push_pair = { 'event_name' => 'push', 'before' => baseline, 'after' => candidate } if profile == 'quick'
          end
        when 'schedule'
          candidate = @repository.commit!(event_sha)
          baseline = @repository.commit!(REFERENCE)
          reason = 'scheduled default event SHA against fixed accepted reference'
        when 'workflow_dispatch'
          inputs = event.fetch('inputs', {})
          requested_candidate = inputs.fetch('candidate_sha', '')
          requested_baseline = inputs.fetch('baseline_sha', '')
          if requested_candidate.empty? && requested_baseline.empty?
            candidate = default_sha
            baseline = @repository.commit!(REFERENCE)
            reason = 'manual captured default against fixed accepted reference'
          else
            candidate = @repository.commit!(requested_candidate)
            baseline = @repository.commit!(requested_baseline)
            reason = 'manual exact candidate/baseline pair'
          end
        else
          raise Error, "Unsupported event: #{event_name}"
        end
        if profile == 'weekly' && baseline != REFERENCE
          raise Error, 'Weekly comparisons require the fixed accepted reference'
        end
        raise Error, 'Baseline and candidate must differ' if baseline == candidate

        lineage ||= @repository.release_lineage(candidate)
        unless push_pair || @repository.ancestor?(baseline, candidate) || (profile == 'weekly' && baseline == REFERENCE && lineage)
          raise Error, 'Baseline must be an ancestor of candidate'
        end

        paths = @repository.paths(baseline, candidate)
        forced = %w[schedule workflow_dispatch].include?(event_name)
        { schema_version: 1, event_name:, profile:, candidate_sha: candidate, baseline_sha: baseline,
          captured_default_sha: default_sha, release_lineage: lineage, fixed_reference_sha: REFERENCE, reason:, push_pair:,
          relevant: forced || paths.any? { |path| RELEVANT.match?(path) }, changed_paths: paths }
      rescue KeyError, TypeError => e
        raise Error, "Incomplete event: #{e.message}"
      end
    end

    def self.aggregate!(result, outcome)
      raise Error, "Performance job did not succeed: #{result}" unless result == 'success'
      raise Error, 'Performance job has no explicit outcome' unless %w[compared no-work].include?(outcome)

      true
    end

    # Preparation runs outside measurement and never resolves a second graph.
    class Campaign
      CONFIGS = %w[.ruby-version flake.nix flake.lock Gemfile servers/ruby/Gemfile clients/ruby/Gemfile].freeze
      SPECS = %w[servers/ruby/haveapi.gemspec clients/ruby/haveapi-client.gemspec].freeze
      UNSET = (ENV.keys.grep(/\ABUNDLE/) + %w[RUBYOPT RUBYLIB RUBYGEMS_GEMDEPS]).to_h { |key| [key, nil] }.freeze

      def initialize(repository:, selection:, evidence:, sources:)
        @repository = repository
        @selection = selection
        @evidence = File.expand_path(evidence)
        @sources = File.expand_path(sources)
      end

      def run
        raise Error, 'Selection schema mismatch' unless @selection.fetch('schema_version') == 1
        raise Error, 'Only relevant selections can run' unless @selection.fetch('relevant') == true
        raise Error, 'Unknown selected profile' unless %w[quick weekly].include?(@selection.fetch('profile'))
        raise Error, 'Source directory already exists' if File.exist?(@sources)

        candidate = @repository.commit!(@selection.fetch('candidate_sha'))
        baseline = @repository.commit!(@selection.fetch('baseline_sha'))
        @release_lineage = @repository.release_lineage(candidate)
        push = Performance.push_pair!(@selection, baseline:, candidate:)
        unless baseline != candidate && (push || @repository.ancestor?(baseline, candidate) ||
               (@selection.fetch('profile') == 'weekly' && baseline == REFERENCE && @release_lineage))
          raise Error, 'Invalid selected ancestry'
        end
        if @selection.fetch('profile') == 'weekly' && baseline != REFERENCE
          raise Error, 'Weekly comparisons require the fixed accepted reference'
        end
        raise Error, 'Harness checkout differs from candidate' unless @repository.git('rev-parse', 'HEAD').strip == candidate
        raise Error, 'Harness checkout has tracked changes' unless @repository.git('diff', 'HEAD', '--').empty?

        FileUtils.mkdir_p(@evidence)
        File.write(File.join(@evidence, 'release-lineage.json'), JSON.pretty_generate(@release_lineage)) if @release_lineage
        FileUtils.mkdir(@sources)
        roots = { baseline: export(:baseline, baseline), candidate: export(:candidate, candidate) }
        verify_dependencies(roots)
        retain_inputs
        roots.each_value { |root| command!('make', '--no-print-directory', '--silent', 'doc', chdir: root) }
        runner = File.join(@repository.root, 'servers/ruby/benchmarks/endpoints.rb')
        budget = File.join(@repository.root, 'servers/ruby/benchmarks/performance_budgets.json')
        command = [RbConfig.ruby, runner, 'run', '--baseline-root', roots[:baseline], '--baseline-sha', baseline,
                   '--candidate-root', roots[:candidate], '--candidate-sha', candidate,
                   '--profile', @selection.fetch('profile'), '--budgets', budget, '--output', File.join(@evidence, 'results')]
        if push
          selection_path = File.join(@evidence, 'push-event.json')
          File.write(selection_path, JSON.pretty_generate(@selection))
          command += ['--push-event', selection_path]
        end
        File.write(File.join(@evidence, 'runner-command.json'), JSON.pretty_generate(command))
        status = nil
        File.open(File.join(@evidence, 'runner.stdout'), 'w') do |stdout|
          File.open(File.join(@evidence, 'runner.stderr'), 'w') do |stderr|
            pid = Process.spawn(UNSET, *command, chdir: @repository.root, out: stdout, err: stderr)
            status = Process.wait2(pid).last
          end
        end
        code = status.exitstatus || 3
        File.write(File.join(@evidence, 'runner.exit'), "#{code}\n")
        raise Error, 'Runner returned an unknown exit code' unless [0, 1, 2, 3].include?(code)

        report = JSON.parse(File.read(File.join(@evidence, 'results/report.json')))
        expected = { 0 => %w[pass inconclusive], 1 => ['regression'], 3 => ['error'] }.fetch(code, [])
        unless report.fetch('schema_version').eql?(Performance::SAMPLE_SCHEMA) && expected.include?(report.fetch('status')) &&
               report.fetch('baseline_sha') == baseline && report.fetch('candidate_sha') == candidate
          raise Error, 'Runner report/exit/source identity mismatch'
        end

        write_summary(report) if ENV['GITHUB_STEP_SUMMARY']
        code
      end

      private

      def write_summary(report)
        File.open(ENV.fetch('GITHUB_STEP_SUMMARY'), 'a') do |file|
          file.puts("### Performance comparison: #{report.fetch('status')}", '',
                    "`#{report.fetch('baseline_sha')}` → `#{report.fetch('candidate_sha')}`", '')
          next if report.fetch('status') == 'error'

          file.puts('| Workload | Outcome | Wall | CPU | Allocations | Raw changed | Canonical changed | Bytes/request (before → after) | Byte delta |',
                    '| --- | --- | --- | --- | --- | --- | --- | --- | --- |')
          report.fetch('cases').each do |item|
            response = item.fetch('responses')
            bytes = response.fetch('bytes_per_request')
            label = "#{item.fetch('id')} #{JSON.generate(item.fetch('dimensions'))}"
            file.puts("| #{label} | #{item.fetch('classification')} | #{item.fetch('timing').fetch('wall_seconds').fetch('classification')} | " \
                      "#{item.fetch('timing').fetch('cpu_seconds').fetch('classification')} | #{item.fetch('allocations').fetch('classification')} | " \
                      "#{response.fetch('raw_changed')} | #{response.fetch('canonical_changed')} | #{format('%.2f → %.2f', bytes.fetch('baseline'), bytes.fetch('candidate'))} | " \
                      "#{format('%+.2f (%+.2f%%)', bytes.fetch('delta'), bytes.fetch('delta_percent'))} |")
          end
        end
      end

      def export(name, sha)
        archive = File.join(@evidence, "#{name}-source.tar")
        File.open(archive, 'wb') do |file|
          pid = Process.spawn('git', '-C', @repository.root, 'archive', '--format=tar', sha, out: file)
          raise Error, 'Source archive failed' unless Process.wait2(pid).last.success?
        end
        File.write(File.join(@evidence, "#{name}-tree.txt"), @repository.git('ls-tree', '-r', '--full-tree', sha))
        File.write("#{archive}.sha256", "#{Digest::SHA256.file(archive).hexdigest}\n")
        root = File.join(@sources, name.to_s)
        FileUtils.mkdir(root)
        command!('tar', '-xf', archive, '-C', root)
        root
      end

      def command!(*command, chdir: @repository.root)
        output, error, status = Open3.capture3(UNSET, *command, chdir:)
        File.open(File.join(@evidence, 'preparation.log'), 'a') { |f| f.puts(JSON.generate(command), output, error) }
        raise Error, "Preparation failed: #{command.first}" unless status.success?

        output
      end

      def verify_dependencies(roots)
        if @release_lineage
          roots.each_value do |root|
            (SPECS + ['clients/rust/haveapi-rust-client.gemspec']).each { |path| gemspec(root, path) }
          end
          receipts = roots.transform_values do |root|
            contents = Performance::Release.paths(@selection.fetch('profile')).to_h { |path| [path, File.read(File.join(root, path))] }
            Performance::Release.capture(contents)
          end
          File.write(File.join(@evidence, 'dependency-compatibility.json'), JSON.pretty_generate(receipts))
          unless receipts[:baseline].fetch('normalized_sha256').except('flake.nix', 'flake.lock') == receipts[:candidate].fetch('normalized_sha256').except('flake.nix', 'flake.lock')
            raise Error, 'Dependency inputs differ; reviewed environment migration required'
          end

          return
        end

        configs = CONFIGS.dup
        specs = SPECS.dup
        configs << 'clients/rust/Gemfile'
        specs << 'clients/rust/haveapi-rust-client.gemspec'
        manifests = roots.transform_values do |root|
          contents = configs.to_h { |path| [path, File.read(File.join(root, path))] }
          preparation = Performance::Release.json_preparation(contents)
          { configs: contents.merge(preparation.fetch('normalized_contents')).except('flake.nix', 'flake.lock').transform_values { |text| Digest::SHA256.hexdigest(text) },
            contributor_flakes: contents.slice('flake.nix', 'flake.lock'),
            json_preparation: preparation,
            gemspecs: specs.to_h { |path| [path, gemspec(root, path)] } }
        end
        File.write(File.join(@evidence, 'dependency-compatibility.json'), JSON.pretty_generate(manifests))
        raise Error, 'Dependency inputs differ; reviewed environment migration required' unless manifests[:baseline].except(:json_preparation, :contributor_flakes) == manifests[:candidate].except(:json_preparation, :contributor_flakes)
      end

      def gemspec(root, path)
        Performance.gemspec(root, path)
      rescue Performance::ContractError => e
        raise Error, e.message
      end

      def retain_inputs
        paths = %w[flake.nix flake.lock .ruby-version Gemfile servers/ruby/Gemfile clients/rust/Gemfile]
        paths += Performance::BENCHMARK_INPUTS
        hashes = paths.to_h do |path|
          source = File.join(@repository.root, path)
          raise Error, "Missing prepared input: #{path}" unless File.file?(source)

          destination = File.join(@evidence, 'inputs', path)
          FileUtils.mkdir_p(File.dirname(destination))
          FileUtils.cp(source, destination)
          [path, Digest::SHA256.file(source).hexdigest]
        end
        File.write(File.join(@evidence, 'input-sha256.json'), JSON.pretty_generate(hashes))
        File.write(File.join(@evidence, 'runtime.json'), JSON.pretty_generate(description: RUBY_DESCRIPTION,
                                                                              executable: RbConfig.ruby, gem_paths: Gem.path))
      end
    end

    def self.cli(argv)
      command = argv.shift
      options = {}
      OptionParser.new do |parser|
        %w[event event-name event-sha default-sha repository output github-output selection evidence sources result outcome].each do |name|
          parser.on("--#{name} VALUE") { |value| options[name.tr('-', '_').to_sym] = value }
        end
      end.parse!(argv)
      raise Error, 'Unexpected positional arguments' unless argv.empty?

      case command
      when 'resolve'
        selection = Resolver.new(Repository.new(options.fetch(:repository))).resolve(
          event_name: options.fetch(:event_name), event: JSON.parse(File.read(options.fetch(:event))),
          event_sha: options.fetch(:event_sha), default_sha: options[:default_sha]
        )
        File.write(options.fetch(:output), JSON.pretty_generate(selection))
        if options[:github_output]
          File.open(options[:github_output], 'a') do |file|
            %i[relevant profile candidate_sha baseline_sha].each { |key| file.puts("#{key}=#{selection.fetch(key)}") }
          end
        end
        puts JSON.generate(selection)
        0
      when 'run'
        Campaign.new(repository: Repository.new(options.fetch(:repository)),
                     selection: JSON.parse(File.read(options.fetch(:selection))),
                     evidence: options.fetch(:evidence), sources: options.fetch(:sources)).run
      when 'aggregate'
        aggregate!(options.fetch(:result), options.fetch(:outcome))
        0
      else
        raise Error, 'Expected resolve, run or aggregate'
      end
    rescue StandardError => e
      warn "#{e.class}: #{e.message}"
      3
    end
  end
end

exit HaveAPI::PerformanceCI.cli(ARGV) if $0 == __FILE__
