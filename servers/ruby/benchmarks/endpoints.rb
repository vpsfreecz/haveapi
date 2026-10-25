require 'base64'
require 'fileutils'
require 'etc'
require 'open3'
require 'optparse'
require 'rbconfig'
require 'socket'
require_relative 'performance_compare'

module HaveAPI
  module Performance
    ROOT = File.expand_path('../../..', __dir__)
    FIXTURE_PATHS = %w[performance_endpoint_fixture.rb performance_sqlite_fixture.rb documentation_performance_fixture.rb].freeze

    class DocumentationScenario
      # Only benchmark processes install this observer. It does not change the
      # authorization result or retain a request beyond its timed call.
      module AuthorizationObserver
        def authorized?(...)
          record = Thread.current[:haveapi_performance_documentation]
          record[:authorizations] += 1 if record
          super
        end
      end

      def self.cases(profile:)
        quick = %w[docs.options docs.html_resources docs.html_actions].map { |id| { id:, dimensions: { size: 8 } } }
        return quick if profile == 'quick'

        quick + %w[docs.options docs.html_resources docs.html_actions].product(%w[admin member]).map do |id, user|
          { id:, dimensions: { size: 16, user: } }
        end + %w[rust.async_example rust.async_auth rust.blocking_example rust.blocking_auth].map do |id|
          { id:, dimensions: { size: 16, user: 'admin' } }
        end
      end

      def initialize(spec)
        @id = spec.fetch(:id)
        dimensions = spec.fetch(:dimensions)
        size = dimensions.fetch(:size)
        @user = dimensions.fetch(:user, 'admin')
        resources, actions = @id == 'docs.html_actions' ? [1, size] : [size, 1]
        @server = DocumentationPerformanceFixture.build(resource_count: resources, actions_per_resource: actions, rust: @id.start_with?('rust.'))
        Authorization.prepend(AuthorizationObserver) unless Authorization.ancestors.include?(AuthorizationObserver)
        @request = Rack::MockRequest.new(@server.app)
        @headers = { 'HTTP_HOST' => 'example.test', 'HTTP_ACCEPT_LANGUAGE' => 'en',
                     'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64("#{@user}:fixture-only")}" }
        @url = 'http://example.test/benchmark/api/v1/'
        prepare_rust if @id.start_with?('rust.')
      end

      def reset!(iterations:)
        @operations = Array.new(iterations) { { queries: 0, authorizations: 0, executions: 0 } }
        @index = 0
      end

      def call
        Thread.current[:haveapi_performance_documentation] = @operations.fetch(@index)
        @index += 1
        if @id.start_with?('rust.')
          kind = @id.end_with?('_auth') ? :auth : :example
          result = @profile.adapter.render(kind:, context: @context, mode: @id.include?('blocking') ? :blocking : :async,
                                           auth_method: :basic, auth_description: @auth)
          Rack::MockResponse.new(200, { 'content-type' => 'application/json' }, JSON.generate(result))
        elsif @id == 'docs.options'
          @request.options(@url, **@headers, 'HTTP_ACCEPT' => 'application/json')
        else
          @request.get(@url, **@headers)
        end
      ensure
        Thread.current[:haveapi_performance_documentation] = nil
      end

      def validate!(response, index:)
        @operations.fetch(index)
        raise ContractError, 'Documentation response failed' unless response.status == 200

        if @id.start_with?('rust.')
          value = JSON.parse(response.body)
          raise ContractError, 'Rust code missing' unless value['status'] == 'code' && value['code'].is_a?(String) && !value['code'].empty?

          return { http_status: 200, envelope_status: nil, body_bytes: response.body.bytesize,
                   body_sha256: Digest::SHA256.hexdigest(response.body), canonical_body: value }
        end
        if @id == 'docs.options'
          identity = Identity.json(response)
          raise ContractError, 'Documentation resources missing' unless identity[:canonical_body].fetch('response').fetch('resources').any?

          return identity
        end
        unless response.body.include?('PUBLIC_SAMPLE_0') && response.body.include?('init-python-sync') && response.body.include?('init-examples')
          raise ContractError, 'Documentation panels missing'
        end
        if response.body.include?('ADMIN_ONLY_REQUEST') != (@user == 'admin')
          raise ContractError, 'Documentation authorization mismatch'
        end

        { http_status: 200, envelope_status: nil, body_bytes: response.body.bytesize,
          body_sha256: Digest::SHA256.hexdigest(response.body), canonical_sha256: Digest::SHA256.hexdigest(response.body) }
      end

      def counters
        raise ContractError, 'Documentation operations missing' unless @index == @operations.length

        { operations: @operations }
      end

      def close; end

      private

      def prepare_rust
        response = @request.options(@url, **@headers, 'HTTP_ACCEPT' => 'application/json')
        description = JSON.parse(response.body, symbolize_names: true).fetch(:response)
        @profile = @server.documentation_client_profiles(1).fetch(:rust)
        resource = description.fetch(:resources).fetch(:resource0)
        action = resource.fetch(:actions).fetch(:action0)
        @context = ClientExample::Context.new(version: 1, host: 'example.test', base_url: 'http://example.test/benchmark/api/',
                                              version_url: @url, description:, profile: @profile, resource_path: ['resource0'],
                                              resource:, action_name: 'action0', action:, sample: action.fetch(:examples).first)
        @auth = description.fetch(:authentication).fetch(:basic)
      end
    end

    class Worker
      def initialize(request)
        @request = request
      end

      def run
        started = monotonic
        ENV['RACK_ENV'] = 'test'
        ENV['LC_ALL'] = 'C.UTF-8'
        ENV['LANG'] = 'C.UTF-8'
        ENV['TZ'] = 'UTC'
        ENV['RUBY_YJIT_ENABLE'] = '0'
        policy = RUNTIME_POLICY.merge('yjit' => (defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?) || false,
                                      'rjit' => (defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?) || false)
        raise ContractError, 'JIT must be disabled before worker startup' unless policy == RUNTIME_POLICY

        source = File.realpath(@request.fetch('source_root'))
        %w[servers/ruby clients/ruby clients/rust].reverse_each { |component| $:.unshift(File.join(source, component, 'lib')) }
        require 'active_record'
        require 'sqlite3'
        require 'haveapi'
        require 'haveapi/client'
        require 'rack/mock'
        require 'haveapi/rust_client/documentation' if @request.fetch('profile') == 'weekly'
        FIXTURE_PATHS.each { |name| require File.join(ROOT, 'servers/ruby/test_support', name) }
        load_seconds = monotonic - started
        inventory = self.class.inventory(@request.fetch('profile'))
        order = @request.fetch('workload_order', 'forward')
        raise ContractError, 'Unknown workload order' unless %w[forward reverse].include?(order)

        selected = order == 'reverse' ? inventory.reverse : inventory
        results = selected.map do |spec|
          count = @request.fetch('counts').fetch(Identity.key(JSON.parse(JSON.generate(spec))), 1)
          build_started = monotonic
          scenario = self.class.build(spec)
          stages = { build_seconds: monotonic - build_started }
          begin
            stages[:warmups] = Array.new(2) { measure(scenario, count).fetch(:stages) }
            result = measure(scenario, count)
            stages[:measured] = result.delete(:stages)
          ensure
            close_started = monotonic
            scenario.close
            stages[:close_seconds] = monotonic - close_started
          end
          result.merge(spec).merge(stages:)
        end
        { schema_version: 1, inventory:, cases: results, source: source_identity(source), environment: environment,
          inputs: self.class.inputs(source, @request.fetch('profile')), fixture_sha256: self.class.fixture_hashes,
          runtime_policy: policy, workload_order: order, host: host_identity,
          stages: { require_load_seconds: load_seconds, worker_seconds: monotonic - started } }
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def host_identity
        cpu = File.file?('/proc/cpuinfo') ? File.read('/proc/cpuinfo')[/^model name\s*:\s*(.+)$/, 1] : RbConfig::CONFIG['host_cpu']
        { hostname: Socket.gethostname, os: "#{RbConfig::CONFIG['host_os']} #{Etc.uname[:release]}", cpu: cpu.to_s }
      end

      def self.inventory(profile)
        PROFILES.fetch(profile)
        PerformanceFixtures::Endpoints.cases(profile:) + PerformanceFixtures::SQLite.cases(profile:) + DocumentationScenario.cases(profile:)
      end

      def self.build(spec)
        case spec.fetch(:id)
        when /^api\./ then PerformanceFixtures::Endpoints.build(spec)
        when /^sqlite\./ then PerformanceFixtures::SQLite.build(spec)
        else DocumentationScenario.new(spec)
        end
      end

      def measure(scenario, iterations)
        raise ContractError, 'Invalid worker iteration count' unless iterations.is_a?(Integer) && iterations.between?(1, 2000)

        reset_started = monotonic
        responses = Array.new(iterations)
        scenario.reset!(iterations:)
        GC.start
        reset_gc_seconds = monotonic - reset_started
        allocated = GC.stat(:total_allocated_objects)
        cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
        wall = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        iterations.times { |index| responses[index] = scenario.call }
        wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall
        cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu
        allocations = GC.stat(:total_allocated_objects) - allocated
        validation_started = monotonic
        bodies = {}
        outputs = responses.each_with_index.map do |response, index|
          identity = scenario.validate!(response, index:)
          identity = identity.transform_keys(&:to_s)
          raw_digest = Digest::SHA256.hexdigest(response.body)
          unless identity.fetch('body_sha256') == raw_digest && identity.fetch('body_bytes') == response.body.bytesize &&
                 identity.fetch('http_status') == response.status
            raise ContractError, 'Fixture output identity is incorrect'
          end

          canonical = identity.delete('canonical_body')
          if canonical && !identity.has_key?('canonical_sha256')
            canonical = Identity.canonical(canonical)
            identity['canonical_sha256'] = Digest::SHA256.hexdigest(JSON.generate(canonical))
          end
          raise ContractError, 'Missing canonical identity' unless identity.has_key?('canonical_sha256')

          if bodies.has_key?(raw_digest) && bodies[raw_digest][:body] != response.body
            raise ContractError, 'Raw output digest collision'
          end

          bodies[raw_digest] ||= { body: response.body, canonical_body: canonical }
          identity
        end
        counters = scenario.counters
        unless counters.fetch(:operations).length == iterations
          raise ContractError, 'Missing per-operation counters'
        end

        { operations: iterations, wall_seconds: wall / iterations, cpu_seconds: cpu / iterations,
          allocated_objects: allocations.to_f / iterations, outputs:, bodies:, counters:,
          stages: { reset_gc_seconds:, request_seconds: wall, validation_seconds: monotonic - validation_started } }
      end

      def self.fixture_hashes
        paths = FIXTURE_PATHS.map { |name| "servers/ruby/test_support/#{name}" }
        paths += %w[servers/ruby/benchmarks/endpoints.rb servers/ruby/benchmarks/performance_compare.rb]
        paths.to_h { |path| [path, Digest::SHA256.file(File.join(ROOT, path)).hexdigest] }
      end

      def self.inputs(source, profile)
        paths = %w[flake.lock servers/ruby/Gemfile servers/ruby/haveapi.gemspec clients/ruby/Gemfile clients/ruby/haveapi-client.gemspec]
        paths += %w[clients/rust/Gemfile clients/rust/haveapi-rust-client.gemspec] if profile == 'weekly'
        manifests = paths.to_h do |path|
          target = File.join(source, path)
          raise ContractError, "Missing dependency input #{target}" unless File.file?(target)

          [path, Digest::SHA256.file(target).hexdigest]
        end
        lock_paths = %w[Gemfile.lock servers/ruby/Gemfile.lock]
        lock_paths << 'clients/rust/Gemfile.lock' if profile == 'weekly'
        locks = lock_paths.to_h do |path|
          target = File.join(ROOT, path)
          raise ContractError, "Missing resolved lock #{target}" unless File.file?(target)

          [path, Digest::SHA256.file(target).hexdigest]
        end
        { manifests:, locks: }
      end

      def environment
        { ruby: { engine: RUBY_ENGINE, version: RUBY_VERSION, platform: RUBY_PLATFORM,
                  abi: RbConfig::CONFIG.fetch('ruby_version'), executable: RbConfig.ruby },
          gems: Gem.loaded_specs.except('haveapi', 'haveapi-client', 'haveapi-rust-client')
                   .sort.to_h.transform_values { |spec| { version: spec.version.to_s, platform: spec.platform.to_s } } }
      end

      def source_identity(source)
        methods = { 'servers/ruby/lib/haveapi/server.rb' => Server.instance_method(:mount),
                    'servers/ruby/lib/haveapi/action.rb' => Action.instance_method(:exec),
                    'servers/ruby/lib/haveapi/model_adapters/active_record.rb' => ModelAdapters::ActiveRecord.method(:handle?),
                    'clients/ruby/lib/haveapi/client/client.rb' => Client::Client.instance_method(:initialize) }
        if @request['profile'] == 'weekly'
          methods['clients/rust/lib/haveapi/rust_client/documentation.rb'] = RustClient::Documentation.instance_method(:render)
        end
        methods.each do |path, method|
          raise ContractError, "Wrong loaded source for #{path}" unless File.identical?(method.source_location.first, File.join(source, path))
        end
        loaded = $".grep(%r{/(?:servers/ruby|clients/ruby|clients/rust)/lib/}).to_h do |path|
          real = File.realpath(path)
          raise ContractError, "Runtime escaped selected source: #{real}" unless real.start_with?("#{source}/")

          [real.delete_prefix("#{source}/"), Digest::SHA256.file(real).hexdigest]
        end
        { root: source, sha: @request.fetch('source_sha'), loaded_sources: loaded }
      end
    end

    class CLI
      EXIT_CODES = { 'pass' => 0, 'regression' => 1, 'inconclusive' => 2, 'error' => 3 }.freeze

      def initialize(argv)
        @argv = argv.dup
        @mode = @argv.shift
        @options = { profile: 'quick' }
      end

      def execute
        if @argv == ['--help'] || @mode == '--help'
          puts 'endpoints.rb run --baseline-root PATH --baseline-sha SHA --candidate-root PATH --candidate-sha SHA --profile quick|weekly --budgets FILE --output NEWDIR'
          puts 'endpoints.rb compare --input samples.json --budgets FILE --output NEWDIR'
          return 0
        end
        return worker if @mode == 'worker'

        parse
        destination = File.expand_path(@options.fetch(:output))
        raise ContractError, 'Output directory must not exist' if File.exist?(destination)

        @output = destination
        FileUtils.mkdir_p(@output)
        budget_path = @options.fetch(:budgets)
        budgets = Identity.parse(File.read(budget_path))
        digest = Digest::SHA256.file(budget_path).hexdigest
        samples = @mode == 'run' ? run_samples(digest) : Identity.parse(File.read(@options.fetch(:input)))
        File.write(File.join(@output, 'samples.json'), JSON.pretty_generate(samples)) if @mode == 'run'
        report = Comparator.new(samples, budgets, budget_sha256: digest).compare
        File.write(File.join(@output, 'report.json'), JSON.pretty_generate(report))
        puts JSON.generate(status: report.fetch('status'), report: File.join(@output, 'report.json'))
        EXIT_CODES.fetch(report.fetch('status'))
      rescue StandardError, LoadError => e
        report = { schema_version: 1, status: 'error', error: { class: e.class.name, message: e.message } }
        %i[baseline_sha candidate_sha profile].each { |key| report[key] = @options[key] if @options.has_key?(key) }
        report[:harness_sha256] = Identity.digest(Worker.fixture_hashes) if FIXTURE_PATHS.all? { |name| File.file?(File.join(ROOT, 'servers/ruby/test_support', name)) }
        File.write(File.join(@output, 'report.json'), JSON.pretty_generate(report)) if @output && File.directory?(@output)
        warn JSON.generate(report)
        3
      end

      private

      def parse
        raise ContractError, 'Expected run or compare' unless %w[run compare].include?(@mode)

        OptionParser.new do |parser|
          %w[baseline-root baseline-sha candidate-root candidate-sha profile budgets output input].each do |name|
            parser.on("--#{name} VALUE") { |value| @options[name.tr('-', '_').to_sym] = value }
          end
        end.parse!(@argv)
        raise ContractError, 'Unexpected arguments' unless @argv.empty?

        PROFILES.fetch(@options.fetch(:profile))
        required = @mode == 'run' ? %i[baseline_root baseline_sha candidate_root candidate_sha budgets output] : %i[input budgets output]
        required.each { |key| @options.fetch(key) }
      end

      def worker
        raise ContractError, 'Unexpected worker arguments' unless @argv.empty?

        result = Worker.new(Identity.parse($stdin.read)).run
        serialization_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        serialized = JSON.generate(result)
        serialization_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - serialization_started
        # Add the serialization receipt without serializing the response trees a
        # second time solely to report the first serialization's duration.
        puts "#{serialized.delete_suffix('}')},\"serialization_seconds\":#{serialization_seconds}}"
        0
      end

      def git(*args)
        output, status = Open3.capture2('git', '-C', ROOT, *args, err: File::NULL)
        raise ContractError, "Cannot verify source object: git #{args.first}" unless status.success?

        output
      end

      def verify_source(role)
        sha = @options.fetch(:"#{role}_sha")
        raise ContractError, 'Source SHA must be full immutable SHA' unless sha.match?(/\A[0-9a-f]{40}\z/) && sha != '0' * 40

        root = File.realpath(@options.fetch(:"#{role}_root"))
        git('cat-file', '-e', "#{sha}^{commit}")
        files = git('ls-tree', '-rz', '--full-tree', sha).split("\0")
        graph = {}
        files.each do |entry|
          metadata, path = entry.split("\t", 2)
          mode, kind, expected = metadata.split
          raise ContractError, "Unsupported source entry #{path}" unless kind == 'blob'

          target = File.join(root, path)
          contents = mode == '120000' ? File.readlink(target) : File.binread(target)
          actual = Digest::SHA1.hexdigest("blob #{contents.bytesize}\0#{contents}")
          raise ContractError, "Source tree mismatch #{role}:#{path}" unless actual == expected

          graph[path] = Digest::SHA256.hexdigest(contents)
        end
        { root:, sha:, tracked_files: files.length, files_sha256: graph, tree: git('rev-parse', "#{sha}^{tree}").strip }
      end

      def run_samples(digest)
        policy = PROFILES.fetch(@options.fetch(:profile))
        Performance.validate_source_pair(profile: @options[:profile], baseline_sha: @options[:baseline_sha],
                                         candidate_sha: @options[:candidate_sha])

        sources = %w[baseline candidate].to_h { |role| [role, verify_source(role)] }
        @sources = JSON.parse(JSON.generate(sources))
        git('merge-base', '--is-ancestor', @options[:baseline_sha], @options[:candidate_sha])
        if @options[:profile] == 'weekly'
          git('merge-base', '--is-ancestor', REFERENCE, @options[:candidate_sha])
        end
        pilot = child('baseline', {}, 'pilot')
        inventory = pilot.fetch('inventory')
        counts = pilot.fetch('cases').to_h do |item|
          count = (0.150 / item.fetch('wall_seconds')).ceil.clamp(1, 2000)
          [Identity.key(item), count]
        end
        cases = inventory.map do |spec|
          observed = pilot['cases'].find { |item| Identity.key(item) == Identity.key(spec) }
          count = counts.fetch(Identity.key(spec))
          spec.merge('iterations' => count, 'pilot' => observed.merge('selected_iterations' => count,
                                                                      'target_seconds' => 0.150, 'estimated_target_reached' => observed['wall_seconds'] * count >= 0.150),
                     'self_pairs' => [], 'pairs' => [])
        end
        policy[:self_pairs].times do |index|
          workload_order = index.even? ? 'forward' : 'reverse'
          left = child('baseline', counts, "aa-#{index}-a", workload_order)
          right = child('baseline', counts, "aa-#{index}-b", workload_order)
          append_pair(cases, 'self_pairs', %w[baseline baseline], left, right, workload_order)
        end
        policy[:pairs].times do |index|
          order = index.even? ? %w[baseline candidate] : %w[candidate baseline]
          workload_order = index.even? ? 'forward' : 'reverse'
          observations = order.map { |role| child(role, counts, "ab-#{index}-#{role}", workload_order) }
          baseline = observations.fetch(order.index('baseline'))
          candidate = observations.fetch(order.index('candidate'))
          append_pair(cases, 'pairs', order, baseline, candidate, workload_order)
        end
        { 'schema_version' => 1, 'profile' => @options[:profile], 'baseline_sha' => @options[:baseline_sha],
          'candidate_sha' => @options[:candidate_sha], 'harness_sha256' => Identity.digest(Worker.fixture_hashes),
          'fixture_sha256' => Worker.fixture_hashes, 'budget_sha256' => digest, 'sources' => @sources,
          'environment' => @common.fetch('environment'), 'inputs' => @common.fetch('inputs'), 'observations' => @observations,
          'inventory' => inventory, 'cases' => cases }
      end

      def append_pair(cases, name, order, left, right, workload_order)
        cases.each do |item|
          key = Identity.key(item)
          a = left.fetch('cases').find { |entry| Identity.key(entry) == key }
          b = right.fetch('cases').find { |entry| Identity.key(entry) == key }
          raise ContractError, 'Worker omitted a case' unless a && b

          item[name] << { 'order' => order, 'workload_order' => workload_order, 'baseline' => a, 'candidate' => b }
        end
      end

      def child(role, counts, label, workload_order = 'forward')
        request = { source_root: File.realpath(@options.fetch(:"#{role}_root")), source_sha: @options.fetch(:"#{role}_sha"),
                    profile: @options[:profile], workload_order:, counts: }
        env = ENV.keys.grep(/\ABUNDLE|\ABUNDLER|\ARUBY(?:OPT|LIB)\z/).to_h { |key| [key, nil] }
        env.merge!('LC_ALL' => 'C.UTF-8', 'LANG' => 'C.UTF-8', 'TZ' => 'UTC', 'RUBY_YJIT_ENABLE' => '0', 'RACK_ENV' => 'test')
        process_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        output, errors, status = Open3.capture3(env, RbConfig.ruby, '--disable-yjit', __FILE__, 'worker', stdin_data: JSON.generate(request))
        process_wall_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - process_started
        File.write(File.join(@output, "#{label}.stderr.log"), errors)
        File.write(File.join(@output, "#{label}.json"), output)
        raise ContractError, "Worker failed #{label} (#{status.exitstatus}): #{errors.lines.last}" unless status.success?

        result = JSON.parse(output)
        raise ContractError, 'Worker source identity mismatch' unless result.fetch('source').fetch('root') == request[:source_root] && result['source']['sha'] == request[:source_sha]
        raise ContractError, 'Worker fixture graph mismatch' unless result.fetch('fixture_sha256') == Worker.fixture_hashes

        result.fetch('source').fetch('loaded_sources').each do |path, sha256|
          unless @sources.fetch(role).fetch('files_sha256').fetch(path) == sha256
            raise ContractError, 'Loaded runtime differs from exact source object'
          end
        end

        common = result.slice('environment', 'inputs', 'inventory', 'fixture_sha256')
        @common ||= common
        raise ContractError, 'Incompatible dependency/runtime/input/workload graph' unless common == @common

        @observations ||= {}
        @observations[label] = result.slice('source', 'environment', 'inputs', 'fixture_sha256', 'runtime_policy', 'host',
                                            'workload_order', 'stages', 'serialization_seconds').merge('process_wall_seconds' => process_wall_seconds)
        result.fetch('cases').each { |item| item['observation'] = label }
        result
      end
    end
  end
end

exit HaveAPI::Performance::CLI.new(ARGV).execute if $0 == __FILE__
