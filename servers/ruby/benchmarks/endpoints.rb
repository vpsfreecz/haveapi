require_relative 'performance_compare'
require 'base64'
require 'cgi'
require 'fileutils'
require 'etc'
require 'open3'
require 'optparse'
require 'rbconfig'
require 'socket'
require 'io/wait'

module HaveAPI
  module Performance
    ROOT = File.expand_path('../../..', __dir__)
    FIXTURE_PATHS = %w[performance_endpoint_fixture.rb performance_sqlite_fixture.rb documentation_performance_fixture.rb documentation_oauth_fixture.rb].freeze

    class WorkerTimeout < ContractError
      attr_reader :details

      def initialize(details)
        @details = details
        super("#{details[:kind]}: #{details[:source_sha]} #{details[:workload]} #{details[:phase]} exceeded #{details[:limit_seconds]}s")
      end
    end

    class DocumentationScenario
      attr_reader :documentation_identity

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
        complex = Performance.complex_cases(profile).map { |spec| JSON.parse(JSON.generate(spec), symbolize_names: true) }
        return quick + complex if profile == 'quick'

        quick + complex + %w[docs.options docs.html_resources docs.html_actions].product(%w[admin member]).map do |id, user|
          { id:, dimensions: { size: 16, user: } }
        end + %w[rust.async_example rust.async_auth rust.blocking_example rust.blocking_auth].map do |id|
          { id:, dimensions: { size: 16, user: 'admin' } }
        end
      end

      def initialize(spec)
        @id = spec.fetch(:id)
        dimensions = spec.fetch(:dimensions)
        size = dimensions.fetch(:size, 1)
        @user = dimensions.fetch(:user, 'admin')
        resources, actions = @id == 'docs.html_actions' ? [1, size] : [size, 1]
        # Only HTML on a source owning the optional docs client uses a cookie.
        # The historical f6 source keeps real Basic; API/OPTIONS/direct lanes
        # retain their original provider path and calibrated fixture setup.
        cookie_identity = @id.start_with?('docs.html_') && Server.method_defined?(:documentation_oauth)
        @server = DocumentationPerformanceFixture.build(resource_count: dimensions.fetch(:resources, resources),
                                                        actions_per_resource: dimensions.fetch(:actions, actions),
                                                        samples_per_action: dimensions.fetch(:samples, 1),
                                                        parameters_per_action: dimensions.fetch(:parameters, 2),
                                                        rust: @id.start_with?('rust.') || @id == 'docs.html_rust',
                                                        documentation_oauth: cookie_identity)
        @dimensions = dimensions
        Authorization.prepend(AuthorizationObserver) unless Authorization.ancestors.include?(AuthorizationObserver)
        @request = Rack::MockRequest.new(@server.app)
        @headers = { 'HTTP_HOST' => 'example.test', 'HTTP_ACCEPT_LANGUAGE' => 'en',
                     'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64("#{@user}:fixture-only")}" }
        @url = 'http://example.test/benchmark/api/v1/'
        if cookie_identity
          @documentation_fixture = @server.fixture_documentation_oauth
          @headers.delete('HTTP_AUTHORIZATION')
          @headers['HTTP_COOKIE'] = @server.fixture_documentation_cookie(@user)
          @url = "#{@documentation_fixture.origin}/benchmark/api/v1/"
        end
        @documentation_identity = { mode: cookie_identity ? 'documentation_oauth_cookie' : 'basic', role: @user }
        prepare_rust if @id.start_with?('rust.')
      end

      def reset!(iterations:)
        @operations = Array.new(iterations) { { queries: 0, authorizations: 0, executions: 0 } }
        @index = 0
        @lookup_start = @documentation_fixture&.lookups&.length
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
        unless index.is_a?(Integer) && index >= 0 && index < @index
          raise ContractError, 'Invalid or uncalled documentation operation index'
        end
        raise ContractError, 'Documentation response failed' unless response.status == 200

        if @documentation_fixture
          actual = @documentation_fixture.lookups.drop(@lookup_start)
          expected = Array.new(@index) { [1, "documentation-#{@user}"] }
          raise ContractError, 'Documentation cookie token validation count differs' unless actual == expected
        end

        content_type = @id.start_with?('rust.') || @id == 'docs.options' ? 'application/json' : 'text/html'
        raise ContractError, 'Documentation content type differs' unless response['content-type']&.start_with?(content_type)

        authorizations = if @id.start_with?('rust.')
                           0
                         elsif @id == 'docs.html_rust'
                           (@dimensions.fetch(:resources) * @dimensions.fetch(:actions)) + 1
                         else
                           @dimensions.fetch(:size) + 1
                         end
        unless @operations.fetch(index) == { queries: 0, authorizations:, executions: 0 }
          raise ContractError, 'Documentation operation counters differ'
        end

        return yield(-> { validate_body!(response) }) if block_given?

        validate_body!(response)
      end

      def validate_body!(response)
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
        if response.body.match?(/\bdata-docs(?:\s|=|>)/)
          validate_overview!(response.body)
        else
          validate_monolith!(response.body)
        end
        { http_status: 200, envelope_status: nil, body_bytes: response.body.bytesize,
          body_sha256: Digest::SHA256.hexdigest(response.body), canonical_sha256: Digest::SHA256.hexdigest(response.body) }.tap do |identity|
          identity[:page] = @page if @page
        end
      end

      def validate_monolith!(body)
        @page = { shape: 'monolithic' }
        unless body.include?('PUBLIC_SAMPLE_0') && body.include?('init-python-sync') && body.include?('init-examples')
          raise ContractError, 'Documentation panels missing'
        end
        if body.include?('ADMIN_ONLY_REQUEST') != (@user == 'admin')
          raise ContractError, 'Documentation authorization mismatch'
        end

        return unless @id == 'docs.html_rust'

        actions = @dimensions.fetch(:resources) * @dimensions.fetch(:actions)
        unless body.include?('init-rust-async') && body.include?('init-rust-blocking') &&
               body.include?("example-resource#{@dimensions.fetch(:resources) - 1}-action3-1")
          raise ContractError, 'Full Rust documentation page missing panels/actions/examples'
        end

        markers = %w[ADMIN_ONLY_ACTION ADMIN_ONLY_DEFAULT ADMIN_ONLY_REQUEST ADMIN_ONLY_RESPONSE ADMIN_ONLY_ACTION_SAMPLE admin_field admin_only]
        unless markers.all? { |marker| body.include?(marker) == (@user == 'admin') }
          raise ContractError, 'Full Rust documentation authorization mismatch'
        end

        examples = body.scan(/id="example-resource\d+-(?:action\d+|admin_only)-\d+-examples"/).uniq.length
        expected_examples = (actions * (@dimensions.fetch(:samples) + (@user == 'admin' ? 1 : 0))) + (@user == 'admin' ? 1 : 0)
        unless examples == expected_examples && body.include?('documentation_performance_client')
          raise ContractError, 'Full Rust documentation example inventory mismatch'
        end

        @page = { shape: 'monolithic', actual_examples: examples, resources: @dimensions.fetch(:resources), actions: actions + (@user == 'admin' ? 1 : 0),
                  public_examples: actions * @dimensions.fetch(:samples), user: @user }
      end

      def validate_overview!(body)
        roots = body.scan(/<[^>]+\bdata-docs(?:\s|=|>)[^>]*>/)
        unless body.scan(/\sdata-docs(?=[\s=>])/).length == 1 && roots.length == 1 && roots.first.scan(/\bdata-page="([^"]*)"/).flatten == ['overview']
          raise ContractError, 'Documentation overview root differs'
        end

        forbidden = /id="(?:example-|root-)|PUBLIC_SAMPLE_|ADMIN_ONLY_|admin_field|admin_result/
        raise ContractError, 'Documentation overview contains action data' if body.match?(forbidden)

        resources, actions = documentation_dimensions
        expected = resources.times.map { |index| "resource#{index}" }
        links = body.scan(/<a\b([^>]*\bdata-resource-directory-link[^>]*)>/).map do |attributes|
          href = attributes.first[/\bhref="([^"]*)"/, 1]
          href && CGI.unescapeHTML(href)
        end
        unless !links.empty? && links.all? { |href| href == '/benchmark/api/v1/?page=resources' } &&
               !body.include?('data-resource-link=')
          raise ContractError, 'Documentation overview directory navigation differs'
        end

        %w[0 2 3 5 6 javascript-callback javascript-async typescript-callback typescript-async python-sync python-async].tap do |clients|
          clients.push('rust-async', 'rust-blocking') if @id == 'docs.html_rust'
          clients.each do |client|
            %w[simple thorough].each do |detail|
              suffix = detail == 'thorough' ? '-thorough' : ''
              pattern = %r{<details\b(?=[^>]*\bdata-example-panel\b)(?=[^>]*\bdata-client="#{client}")(?=[^>]*\bdata-detail="#{detail}")(?=[^>]*\bid="init-#{client}#{suffix}")[^>]*>(.*?)</details>}m
              panel = body.match(pattern)
              code = panel && panel[1].match(%r{<pre><code[^>]*>(.*?)</code></pre>}m)
              unless code && !code[1].strip.empty?
                raise ContractError, 'Documentation overview initialization panel missing'
              end
            end
          end
        end
        if @id == 'docs.html_rust' && !body.include?('documentation_performance_client')
          raise ContractError, 'Documentation overview Rust package missing'
        end

        maps = body.scan(%r{<script\b[^>]*\bdata-legacy-anchors\b[^>]*>(.*?)</script>}m)
        raise ContractError, 'Documentation overview legacy map missing' unless maps.length == 1

        anchors = JSON.parse(maps.first.first)
        raise ContractError, 'Documentation overview legacy map invalid' unless anchors.is_a?(Hash)

        expected_anchors = {}
        expected.each do |key|
          destination = "/benchmark/api/v1/?resource=#{key}"
          expected_anchors["root-#{key}"] = destination
          actions.times do |index|
            expected_anchors["root-#{key}-action#{index}"] = destination
            expected_anchors["example-#{key}-action#{index}-"] = destination
          end
        end
        if @user == 'admin'
          expected_anchors['root-resource0-admin_only'] = '/benchmark/api/v1/?resource=resource0'
          expected_anchors['example-resource0-admin_only-'] = '/benchmark/api/v1/?resource=resource0'
        end
        allowed_destinations = expected.map { |key| "/benchmark/api/v1/?resource=#{key}" } +
                               ['/benchmark/api/v1/', '/benchmark/api/v1/?page=resources', '/benchmark/api/v1/?page=authentication']
        unless anchors.values.all? { |destination| allowed_destinations.include?(destination) }
          raise ContractError, 'Documentation overview legacy targets differ'
        end

        actual = anchors.select { |key, _| key.start_with?('root-', 'example-') }
        unless actual == expected_anchors
          raise ContractError, 'Documentation overview authorization or legacy targets differ'
        end

        @page = { shape: 'overview', actual_examples: 0, resources:, actions: (resources * actions) + (@user == 'admin' ? 1 : 0),
                  public_examples: 0, user: @user }
      rescue JSON::ParserError
        raise ContractError, 'Documentation overview legacy map invalid'
      end

      def documentation_dimensions
        size = @dimensions.fetch(:size, 1)
        resources, actions = @id == 'docs.html_actions' ? [1, size] : [size, 1]
        [@dimensions.fetch(:resources, resources), @dimensions.fetch(:actions, actions)]
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

        activate_benchmark_console
        source = File.realpath(@request.fetch('source_root'))
        %w[servers/ruby clients/ruby clients/rust].reverse_each { |component| $:.unshift(File.join(source, component, 'lib')) }
        require 'active_record'
        require 'sqlite3'
        require 'haveapi'
        require 'haveapi/client'
        require 'rack/mock'
        FIXTURE_PATHS.each { |name| require File.join(ROOT, 'servers/ruby/test_support', name) }
        inventory = self.class.inventory(@request.fetch('profile'))
        require 'haveapi/rust_client/documentation' if inventory.any? { |spec| spec[:id].start_with?('rust.') || spec[:id] == 'docs.html_rust' }
        load_seconds = monotonic - started
        order = @request.fetch('workload_order', 'forward')
        raise ContractError, 'Unknown workload order' unless %w[forward reverse].include?(order)

        selected = order == 'reverse' ? inventory.reverse : inventory
        results = selected.map do |spec|
          @current_workload = Identity.key(JSON.parse(JSON.generate(spec)))
          @phase = 'build'
          progress('setup')
          count = @request.fetch('counts').fetch(Identity.key(JSON.parse(JSON.generate(spec))), 1)
          build_started = monotonic
          scenario = self.class.build(spec)
          stages = { build_seconds: monotonic - build_started }
          begin
            warmup_count = @request.fetch('warmup_counts', {}).fetch(@current_workload, 0)
            stages[:warmups] = Array.new(warmup_count == 0 ? 0 : 2) do |index|
              @phase = "warmup-#{index}"
              measure(scenario, warmup_count).fetch(:stages).merge(operations: warmup_count)
            end
            @phase = 'measured'
            result = measure(scenario, count)
            stages[:measured] = result.delete(:stages)
          ensure
            close_started = monotonic
            scenario.close
            stages[:close_seconds] = monotonic - close_started
          end
          result.merge(spec).merge(stages:).tap do |record|
            record[:documentation_identity] = scenario.documentation_identity if scenario.respond_to?(:documentation_identity)
          end
        end
        inputs = if @request['benchmark'] == true
                   self.class.inputs(source, @request.fetch('profile'), release: @request['release_versions'] == true, benchmark: true)
                 elsif @request['release_versions'] == true
                   self.class.inputs(source, @request.fetch('profile'), release: true)
                 else
                   self.class.inputs(source, @request.fetch('profile'))
                 end
        { schema_version: SAMPLE_SCHEMA, inventory:, cases: results, source: source_identity(source), environment: environment,
          inputs:,
          fixture_sha256: self.class.fixture_hashes,
          runtime_policy: policy, workload_order: order, host: host_identity,
          stages: { require_load_seconds: load_seconds, worker_seconds: monotonic - started } }
      end

      def activate_benchmark_console
        return unless @request['benchmark'] == true

        gem 'io-console', '= 0.9.4'
        require 'io/console'
      end
      private :activate_benchmark_console

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
        raise ContractError, 'Invalid worker iteration count' unless iterations.is_a?(Integer) && iterations.between?(1, MAX_ITERATIONS)

        reset_started = monotonic
        responses = Array.new(iterations)
        scenario.reset!(iterations:)
        GC.start
        reset_gc_seconds = monotonic - reset_started
        progress('request', iterations:)
        allocated = GC.stat(:total_allocated_objects)
        cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
        wall = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        iterations.times { |index| responses[index] = scenario.call }
        wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall
        cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu
        allocations = GC.stat(:total_allocated_objects) - allocated
        progress('setup')
        validation_started = monotonic
        bodies = {}
        proofs = {}
        outputs = {}
        responses.each_with_index do |response, index|
          raw_digest = Digest::SHA256.hexdigest(response.body)
          proof = proofs[raw_digest]
          if proof && proof.fetch(:body) != response.body
            raise ContractError, 'Raw output digest collision'
          end

          # The fixture still checks this operation's index/status/headers and
          # counters. Only its body-only semantic validator can be reused.
          validated = scenario.validate!(response, index:) do |validate_body|
            proof ? proof.fetch(:validation) : validate_body.call
          end
          identity = validated.transform_keys(&:to_s)
          unless identity.fetch('body_sha256') == raw_digest && identity.fetch('body_bytes') == response.body.bytesize &&
                 identity.fetch('http_status') == response.status
            raise ContractError, 'Fixture output identity is incorrect'
          end

          if proof && validated.equal?(proof.fetch(:validation))
            outputs.fetch(raw_digest)['count'] += 1
            next
          end

          canonical = identity.delete('canonical_body')
          unless canonical.nil?
            canonical = Identity.canonical(canonical)
            digest = Digest::SHA256.hexdigest(JSON.generate(canonical))
            unless Identity.canonical(Identity.parse(response.body)) == canonical &&
                   (!identity.has_key?('canonical_sha256') || identity['canonical_sha256'] == digest)
              raise ContractError, 'Fixture raw/canonical output differs'
            end

            identity['canonical_sha256'] = digest
          end
          raise ContractError, 'Missing canonical identity' unless identity.has_key?('canonical_sha256')

          if @request['release_versions'] && scenario.is_a?(DocumentationScenario) &&
             @current_workload.to_s.include?('docs.html_')
            own = File.read(File.join(@request.fetch('source_root'), 'VERSION')).strip
            normalized = Release.html(response.body, own)
            identity['canonical_sha256'] = Digest::SHA256.hexdigest(normalized)
            identity['comparison'] = { 'kind' => 'own-webui-href', 'own_version' => own }
          end

          if proof && (identity != proof.fetch(:output) || canonical != bodies.fetch(raw_digest).fetch(:canonical_body))
            raise ContractError, 'Fixture body proof changed'
          end

          bodies[raw_digest] ||= { body: response.body.dup.freeze, canonical_body: Identity.snapshot(canonical) }.freeze
          proofs[raw_digest] ||= { body: bodies.fetch(raw_digest).fetch(:body), validation: Identity.snapshot(validated),
                                   output: Identity.snapshot(identity) }.freeze
          outputs[raw_digest] ||= proofs.fetch(raw_digest).fetch(:output).merge('count' => 0)
          outputs.fetch(raw_digest)['count'] += 1
        end
        records = scenario.counters.fetch(:operations)
        unless records.length == iterations
          raise ContractError, 'Missing per-operation counters'
        end

        record = records.first
        unless record.keys.map(&:to_s).sort == COUNTERS.sort && record.values.all? { |value| value.is_a?(Integer) && value >= 0 } &&
               records.all? { |operation| operation == record }
          raise ContractError, 'Operation counters are not uniform and valid'
        end

        counters = { operations: iterations, record: record.dup }

        { operations: iterations, wall_seconds: wall / iterations, cpu_seconds: cpu / iterations,
          allocated_objects: allocations.to_f / iterations, outputs: outputs.values, bodies:, counters:,
          stages: { reset_gc_seconds:, request_seconds: wall, validation_seconds: monotonic - validation_started } }
      end

      def self.fixture_hashes
        paths = FIXTURE_PATHS.map { |name| "servers/ruby/test_support/#{name}" }
        paths += %w[servers/ruby/benchmarks/endpoints.rb servers/ruby/benchmarks/performance_compare.rb]
        paths.to_h { |path| [path, Digest::SHA256.file(File.join(ROOT, path)).hexdigest] }
      end

      # One notification at each batch boundary, outside measured allocations.
      # A 30s batch watchdog also bounds every individual request in that batch.
      def progress(state, iterations: nil)
        return unless @request['progress_fd']

        @progress ||= IO.for_fd(@request.fetch('progress_fd'), autoclose: false)
        @progress.syswrite("#{JSON.generate(state:, workload: @current_workload, phase: @phase, iterations:)}\n")
      end

      def self.inputs(source, profile, release: false, benchmark: false)
        paths = %w[Gemfile flake.lock servers/ruby/Gemfile servers/ruby/haveapi.gemspec clients/ruby/Gemfile clients/ruby/haveapi-client.gemspec]
        paths += %w[clients/rust/Gemfile clients/rust/haveapi-rust-client.gemspec]
        paths += %w[.ruby-version flake.nix] if benchmark
        paths |= SourceVersions::PATHS unless release
        raw_manifests = paths.to_h do |path|
          target = File.join(source, path)
          raise ContractError, "Missing dependency input #{target}" unless File.file?(target)

          [path, File.read(target)]
        end
        preparation = Release.json_preparation(raw_manifests)
        manifests = raw_manifests.merge(preparation.fetch('normalized_contents')).transform_values { |text| Digest::SHA256.hexdigest(text) }
        lock_paths = benchmark ? ['servers/ruby/benchmarks/Gemfile.lock'] : %w[Gemfile.lock servers/ruby/Gemfile.lock clients/rust/Gemfile.lock]
        locks = lock_paths.to_h do |path|
          target = File.join(ROOT, path)
          raise ContractError, "Missing resolved lock #{target}" unless File.file?(target)

          [path, Digest::SHA256.file(target).hexdigest]
        end
        if release
          contents = Release.paths(profile).to_h { |path| [path, File.read(File.join(source, path))] }
          receipt = Release.capture(contents)
          versions = [HaveAPI::VERSION, HaveAPI::Client::VERSION]
          versions << HaveAPI::RustClient::VERSION
          raise ContractError, 'Wrong loaded local package version' unless versions.all? { |version| version == receipt.fetch('own_version') }

          result = { manifests: receipt.fetch('normalized_sha256'), locks:, release_versions: receipt }
        else
          versions = SourceVersions.capture(raw_manifests.slice(*SourceVersions::PATHS))
          loaded = [HaveAPI::VERSION, HaveAPI::Client::VERSION, HaveAPI::RustClient::VERSION]
          raise ContractError, 'Wrong loaded local package version' unless loaded.all? { |version| version == versions.fetch('own_version') }

          result = { manifests: manifests.merge(versions.fetch('normalized_sha256')), locks:,
                     json_preparation: preparation, source_versions: versions }
        end
        if benchmark
          result[:manifests] = result.fetch(:manifests).except('flake.nix', 'flake.lock')
          result[:contributor_flakes] = raw_manifests.slice('flake.nix', 'flake.lock').transform_values { |content| { 'content' => content } }
          result[:benchmark] = BENCHMARK_INPUTS.to_h do |path|
            content = File.read(File.join(ROOT, path))
            [path, { 'content' => content, 'sha256' => Digest::SHA256.hexdigest(content) }]
          end
        end
        result
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
        if HaveAPI.const_defined?(:RustClient)
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
      EXIT_CODES = { 'pass' => 0, 'regression' => 1, 'inconclusive' => 0, 'error' => 3 }.freeze

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

        comparison = { 'policy' => Comparator::POLICY, 'comparator_sha256' => Comparator::SOURCE_SHA256 }
        parse
        destination = File.expand_path(@options.fetch(:output))
        raise ContractError, 'Output directory must not exist' if File.exist?(destination)

        @output = destination
        FileUtils.mkdir_p(@output)
        budget_path = @options.fetch(:budgets)
        budgets = Identity.parse(File.read(budget_path))
        digest = Digest::SHA256.file(budget_path).hexdigest
        if @mode == 'run'
          samples = run_samples(digest)
          sample_bytes = JSON.pretty_generate(samples)
          File.binwrite(File.join(@output, 'samples.json'), sample_bytes)
        else
          sample_bytes = File.binread(@options.fetch(:input))
        end
        comparison['samples_sha256'] = Digest::SHA256.hexdigest(sample_bytes)
        samples = Identity.parse(sample_bytes) unless @mode == 'run'
        report = Comparator.new(samples, budgets, budget_sha256: digest).compare.merge('comparison' => comparison)
        File.write(File.join(@output, 'report.json'), JSON.pretty_generate(report))
        puts JSON.generate(status: report.fetch('status'), report: File.join(@output, 'report.json'))
        EXIT_CODES.fetch(report.fetch('status'))
      rescue StandardError, LoadError => e
        report = { schema_version: SAMPLE_SCHEMA, status: 'error', error: { class: e.class.name, message: e.message } }
        report[:error][:details] = e.details if e.is_a?(WorkerTimeout)
        %i[baseline_sha candidate_sha profile].each { |key| report[key] = @options[key] if @options.has_key?(key) }
        if samples.is_a?(Hash)
          report.merge!(samples.slice('baseline_sha', 'candidate_sha', 'profile', 'harness_sha256', 'budget_sha256').transform_keys(&:to_sym))
        end
        report[:comparison] = comparison if comparison
        File.write(File.join(@output, 'report.json'), JSON.pretty_generate(report)) if @output && File.directory?(@output)
        warn JSON.generate(report)
        3
      end

      private

      def parse
        raise ContractError, 'Expected run or compare' unless %w[run compare].include?(@mode)

        OptionParser.new do |parser|
          %w[baseline-root baseline-sha candidate-root candidate-sha profile budgets output input push-event].each do |name|
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

      def ancestor?(left, right)
        _output, status = Open3.capture2('git', '-C', ROOT, 'merge-base', '--is-ancestor', left, right, err: File::NULL)
        raise ContractError, 'Cannot establish source ancestry' unless [0, 1].include?(status.exitstatus)

        status.success?
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

      def verify_runtime
        expected = Identity.parse(File.read(@options.fetch(:budgets))).fetch('environment').fetch('weekly')
        ruby = JSON.parse(JSON.generate(Worker.new({}).environment.fetch(:ruby)))
        raise ContractError, 'Calibration Ruby mismatch' unless ruby == expected.fetch('ruby')

        expected.fetch('gems').each do |name, identity|
          unless Gem::Specification.find_all_by_name(name, identity.fetch('version')).any? { |spec| spec.platform.to_s == identity.fetch('platform') }
            raise ContractError, "Missing calibrated dependency #{name}"
          end
        end
      end

      def run_samples(digest)
        policy = PROFILES.fetch(@options.fetch(:profile))
        verify_runtime
        Performance.validate_source_pair(profile: @options[:profile], baseline_sha: @options[:baseline_sha],
                                         candidate_sha: @options[:candidate_sha])

        sources = %w[baseline candidate].to_h { |role| [role, verify_source(role)] }
        @sources = JSON.parse(JSON.generate(sources))
        @release_lineage = Release.lineage(git: method(:git), ancestor: method(:ancestor?), candidate: @options[:candidate_sha])
        if @options[:push_event]
          raise ContractError, 'Push event exception requires quick profile' unless @options[:profile] == 'quick'

          push = Performance.push_pair!(Identity.parse(File.read(@options[:push_event])), baseline: @options[:baseline_sha], candidate: @options[:candidate_sha])
          raise ContractError, 'Missing exact push pair' unless push
        end
        unless push || ancestor?(@options[:baseline_sha], @options[:candidate_sha]) ||
               (@options[:profile] == 'weekly' && @options[:baseline_sha] == REFERENCE && @release_lineage)
          raise ContractError, 'Baseline must be an ancestor of candidate'
        end

        @sources.each_value do |source|
          Release::VERSIONS.each do |path, name|
            Performance.gemspec(source.fetch('root'), "#{path.split('/lib/').first}/#{name}.gemspec")
          end
        end

        pilot = child('baseline', {}, 'pilot')
        inventory = pilot.fetch('inventory')
        counts = pilot.fetch('cases').to_h do |item|
          count = (policy.fetch(:target) / item.fetch('wall_seconds')).ceil.clamp(1, MAX_ITERATIONS)
          [Identity.key(item), count]
        end
        warmup_counts = pilot.fetch('cases').to_h do |item|
          count = item.fetch('wall_seconds') >= policy.fetch(:target) ? 0 : (0.100 / item.fetch('wall_seconds')).ceil.clamp(1, counts.fetch(Identity.key(item)))
          [Identity.key(item), count]
        end
        @warmup_counts = warmup_counts
        calibration = child('baseline', counts, 'calibration')
        adjusted = false
        calibration.fetch('cases').each do |item|
          key = Identity.key(item)
          duration = item.fetch('wall_seconds') * counts.fetch(key)
          next if warmup_counts.fetch(key) == 0 || duration >= policy.fetch(:adequate) || counts.fetch(key) == MAX_ITERATIONS

          counts[key] = (counts.fetch(key) * policy.fetch(:target) / duration).ceil.clamp(1, MAX_ITERATIONS)
          adjusted = true
        end
        calibration = child('baseline', counts, 'calibration-adjusted') if adjusted
        cases = inventory.map do |spec|
          observed = calibration.fetch('cases').find { |item| Identity.key(item) == Identity.key(spec) }
          count = counts.fetch(Identity.key(spec))
          duration = observed.fetch('wall_seconds') * count
          spec.merge('iterations' => count, 'pilot' => observed.merge('selected_iterations' => count,
                                                                      'warmup_iterations' => warmup_counts.fetch(Identity.key(spec)), 'target_seconds' => policy.fetch(:target),
                                                                      'baseline_batch_seconds' => duration, 'adequate_signal' => duration >= policy.fetch(:adequate),
                                                                      'capped' => count == MAX_ITERATIONS, 'calibration_adjusted' => adjusted), 'self_pairs' => [], 'pairs' => [])
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
        { 'schema_version' => SAMPLE_SCHEMA, 'profile' => @options[:profile], 'baseline_sha' => @options[:baseline_sha],
          'candidate_sha' => @options[:candidate_sha], 'harness_sha256' => Identity.digest(Worker.fixture_hashes),
          'fixture_sha256' => Worker.fixture_hashes, 'budget_sha256' => digest, 'sources' => @sources,
          'environment' => @common.fetch('environment'), 'inputs' => @common.fetch('inputs'), 'release_lineage' => @release_lineage,
          'observations' => @observations,
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
                    profile: @options[:profile], workload_order:, counts:, warmup_counts: @warmup_counts || {}, release_versions: !@release_lineage.nil?, benchmark: true }
        env = ENV.keys.grep(/\ABUNDLE|\ABUNDLER|\ARUBY(?:OPT|LIB|GEMS_GEMDEPS)\z/).to_h { |key| [key, nil] }
        env.merge!('LC_ALL' => 'C.UTF-8', 'LANG' => 'C.UTF-8', 'TZ' => 'UTC', 'RUBY_YJIT_ENABLE' => '0', 'RACK_ENV' => 'test')
        process_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        output, errors, status = capture_worker(env, request, label)
        process_wall_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - process_started
        File.write(File.join(@output, "#{label}.stderr.log"), errors)
        File.write(File.join(@output, "#{label}.json"), output)
        raise ContractError, "Worker failed #{label} (#{status.exitstatus}): #{errors.lines.last}" unless status.success?

        result = JSON.parse(output)
        raise ContractError, 'Unsupported worker sample schema' unless result.fetch('schema_version').eql?(SAMPLE_SCHEMA)
        raise ContractError, 'Worker source identity mismatch' unless result.fetch('source').fetch('root') == request[:source_root] && result['source']['sha'] == request[:source_sha]
        raise ContractError, 'Worker fixture graph mismatch' unless result.fetch('fixture_sha256') == Worker.fixture_hashes

        result.fetch('source').fetch('loaded_sources').each do |path, sha256|
          unless @sources.fetch(role).fetch('files_sha256').fetch(path) == sha256
            raise ContractError, 'Loaded runtime differs from exact source object'
          end
        end

        inputs = result.fetch('inputs')
        Performance.validate_input_receipts(inputs, @sources.fetch(role), profile: @options.fetch(:profile), lineage: @release_lineage)
        expected = Identity.parse(File.read(@options.fetch(:budgets))).fetch('environment').fetch('weekly')
        raise ContractError, 'Calibration environment mismatch' unless result.fetch('environment') == expected

        common = result.slice('environment', 'inventory', 'fixture_sha256').merge('inputs' => Release.graph(inputs))
        @common ||= common
        raise ContractError, 'Incompatible dependency/runtime/input/workload graph' unless common == @common

        @observations ||= {}
        @observations[label] = result.slice('source', 'environment', 'inputs', 'fixture_sha256', 'runtime_policy', 'host',
                                            'workload_order', 'stages', 'serialization_seconds').merge('process_wall_seconds' => process_wall_seconds)
        result.fetch('cases').each { |item| item['observation'] = label }
        result
      end

      def worker_command
        [RbConfig.ruby, '--disable-yjit', __FILE__, 'worker']
      end

      def capture_worker(env, request, label)
        reader, writer = IO.pipe
        request = request.merge(progress_fd: writer.fileno)
        output = errors = ''
        status = nil
        Open3.popen3(env, *worker_command, writer.fileno => writer, pgroup: true) do |input, stdout, stderr, waiter|
          writer.close
          out_thread = Thread.new { stdout.read }
          err_thread = Thread.new { stderr.read }
          begin
            input.write(JSON.generate(request))
            input.close
            event = { 'state' => 'setup' }
            File.open(File.join(@output, "#{label}.progress.jsonl"), 'w') do |log|
              loop do
                limit = event.fetch('state') == 'request' ? REQUEST_LIMIT_SECONDS : SETUP_LIMIT_SECONDS
                unless reader.wait_readable(limit)
                  raise WorkerTimeout.new(kind: event['state'] == 'request' ? 'request_batch_timeout' : 'worker_setup_timeout',
                                          source_sha: request.fetch(:source_sha), workload: event['workload'],
                                          phase: "#{label}/#{event['phase']}", limit_seconds: limit)
                end
                line = reader.gets
                break unless line

                log.write(line)
                log.flush
                event = JSON.parse(line)
                raise ContractError, 'Invalid worker progress' unless %w[request setup].include?(event.fetch('state'))
              end
            end
            unless waiter.join(SETUP_LIMIT_SECONDS)
              raise WorkerTimeout.new(kind: 'worker_setup_timeout', source_sha: request.fetch(:source_sha),
                                      workload: event['workload'], phase: "#{label}/serialization", limit_seconds: SETUP_LIMIT_SECONDS)
            end
            status = waiter.value
          ensure
            unless waiter.join(0)
              begin
                Process.kill('TERM', -waiter.pid)
                waiter.join(0.2)
                Process.kill('KILL', -waiter.pid)
              rescue Errno::ESRCH
                # The owned process group has exited.
              end
              waiter.value
            end
            output = out_thread.value
            errors = err_thread.value
            File.write(File.join(@output, "#{label}.stderr.log"), errors)
            File.write(File.join(@output, "#{label}.json"), output)
          end
        end
        [output, errors, status]
      ensure
        reader&.close unless reader&.closed?
        writer&.close unless writer&.closed?
      end
    end
  end
end

exit HaveAPI::Performance::CLI.new(ARGV).execute if $0 == __FILE__
