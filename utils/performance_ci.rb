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
    RELEVANT = %r{\A(?:servers/ruby/|clients/ruby/|clients/rust/|doc/|utils/performance_ci\.rb\z|utils/copydoc\.sh\z|\.github/workflows/servers-ruby-performance\.yml\z|(?:Gemfile|Makefile|flake\.nix|flake\.lock|\.ruby-version)\z)}

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
          if event.fetch('ref') == "refs/heads/#{branch}"
            baseline = @repository.commit!(event.fetch('before'))
            reason = 'default-branch event before/after batch'
          else
            baseline = @repository.merge_base(candidate, default_sha)
            reason = 'whole feature branch against captured default'
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
        raise Error, 'Baseline must be an ancestor of candidate' unless @repository.ancestor?(baseline, candidate)

        paths = @repository.paths(baseline, candidate)
        forced = %w[schedule workflow_dispatch].include?(event_name)
        { schema_version: 1, event_name:, profile:, candidate_sha: candidate, baseline_sha: baseline,
          captured_default_sha: default_sha, fixed_reference_sha: REFERENCE, reason:,
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
      UNSET = (ENV.keys.grep(/\ABUNDLE/) + %w[RUBYOPT RUBYLIB]).to_h { |key| [key, nil] }.freeze

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
        raise Error, 'Invalid selected ancestry' unless baseline != candidate && @repository.ancestor?(baseline, candidate)
        raise Error, 'Harness checkout differs from candidate' unless @repository.git('rev-parse', 'HEAD').strip == candidate
        raise Error, 'Harness checkout has tracked changes' unless @repository.git('diff', 'HEAD', '--').empty?

        FileUtils.mkdir_p(@evidence)
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
        expected = { 0 => 'pass', 1 => 'regression', 2 => 'inconclusive', 3 => 'error' }.fetch(code)
        unless report.fetch('schema_version') == 1 && report.fetch('status') == expected &&
               report.fetch('baseline_sha') == baseline && report.fetch('candidate_sha') == candidate
          raise Error, 'Runner report/exit/source identity mismatch'
        end

        code
      end

      private

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
        configs = CONFIGS.dup
        specs = SPECS.dup
        if @selection.fetch('profile') == 'weekly'
          configs << 'clients/rust/Gemfile'
          specs << 'clients/rust/haveapi-rust-client.gemspec'
        end
        manifests = roots.transform_values do |root|
          { configs: configs.to_h { |path| [path, Digest::SHA256.file(File.join(root, path)).hexdigest] },
            gemspecs: specs.to_h { |path| [path, gemspec(root, path)] } }
        end
        File.write(File.join(@evidence, 'dependency-compatibility.json'), JSON.pretty_generate(manifests))
        raise Error, 'Dependency inputs differ; reviewed environment migration required' unless manifests[:baseline] == manifests[:candidate]
      end

      def gemspec(root, path)
        script = <<~RUBY
          require 'json'
          spec = Gem::Specification.load(File.basename(ARGV.fetch(0)))
          abort 'Cannot load gemspec' unless spec
          puts JSON.generate(ruby: spec.required_ruby_version.to_s,
                             dependencies: spec.dependencies.map { |d| [d.name, d.type.to_s, d.requirement.to_s] }.sort)
        RUBY
        JSON.parse(command!(RbConfig.ruby, '-e', script, path, chdir: File.dirname(File.join(root, path))))
      end

      def retain_inputs
        paths = %w[flake.nix flake.lock .ruby-version Gemfile Gemfile.lock
                   servers/ruby/Gemfile servers/ruby/Gemfile.lock]
        paths += %w[clients/rust/Gemfile clients/rust/Gemfile.lock] if @selection.fetch('profile') == 'weekly'
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
        File.write(File.join(@evidence, 'flake-metadata.json'), command!('nix', 'flake', 'metadata', '--json', '--no-write-lock-file'))
        system = command!('nix', 'eval', '--raw', '--impure', '--expr', 'builtins.currentSystem').strip
        derivation = command!('nix', 'eval', '--raw', '--no-write-lock-file', ".#devShells.#{system}.default.drvPath").strip
        File.write(File.join(@evidence, 'shell-derivation.txt'), "#{derivation}\n")
        File.write(File.join(@evidence, 'shell-input-graph.txt'), command!('nix-store', '--query', '--requisites', derivation))
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
