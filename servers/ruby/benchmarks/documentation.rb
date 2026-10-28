require 'base64'
require 'digest'
require 'json'
require 'open3'
require 'optparse'
require 'rbconfig'
require 'socket'

module HaveAPI
  # Opt-in measurements; deterministic performance assertions live in the specs.
  class DocumentationBenchmark
    ROOT = File.expand_path('../../..', __dir__)
    FIXTURE = File.expand_path('../test_support/documentation_performance_fixture.rb', __dir__)
    URL = 'http://example.test/benchmark/api/v1/'.freeze
    METRICS = %i[wall_seconds cpu_seconds allocated_objects].freeze

    class InvalidOutput < StandardError
      attr_reader :output

      def initialize(message, output)
        @output = output
        super(message)
      end
    end

    def initialize(argv)
      @options = { shape: 'both', size: 8, resources: 8, actions: 1, samples: 1, parameters: 2,
                   warmup: 1, trials: 3, iterations: 100, lanes: %w[context html], rust: false,
                   user: 'admin', source_root: ROOT }
      parser.parse!(argv)
      raise OptionParser::InvalidArgument, argv.join(' ') unless argv.empty?

      validate_options
    end

    def run
      @git_head = git('rev-parse', 'HEAD')
      unless @git_head || @options[:source_revision]
        raise ArgumentError, 'Source has no Git HEAD; supply --source-revision for an exported tree'
      end

      source_root = @options.fetch(:source_root)
      %w[servers/ruby clients/ruby clients/rust].reverse_each do |component|
        $:.unshift(File.join(source_root, component, 'lib'))
      end
      require 'haveapi'
      require 'rack/mock'
      require FIXTURE
      expected = File.join(source_root, 'servers/ruby/lib/haveapi/documentation_context.rb')
      actual = ClientExample::Context.instance_method(:with).source_location.first
      raise "Context loaded from #{actual}, expected #{expected}" unless File.identical?(actual, expected)

      if @options[:rust]
        require 'haveapi/rust_client/documentation'
        expected_rust = File.join(source_root, 'clients/rust/lib/haveapi/rust_client/documentation.rb')
        actual_rust = RustClient::Documentation.instance_method(:render).source_location.first
        unless File.identical?(actual_rust, expected_rust)
          raise "Rust adapter loaded from #{actual_rust}, expected #{expected_rust}"
        end
      end

      cases = shapes.map { |shape, dimensions| run_case(shape, dimensions) }
      {
        schema_version: 1, status: 'ok', runtime: { description: RUBY_DESCRIPTION, executable: RbConfig.ruby, engine: RUBY_ENGINE,
                                                    version: RUBY_VERSION, platform: RUBY_PLATFORM },
        host: { hostname: Socket.gethostname, os: RbConfig::CONFIG['host_os'] },
        source: source_identity, inputs: input_identity, options: @options, cases:
      }
    end

    private

    def parser
      OptionParser.new do |opts|
        opts.banner = 'Usage: documentation.rb [options] (JSON on stdout)'
        opts.on('--shape SHAPE', %w[resources actions both custom], 'Default: both') { |v| @options[:shape] = v }
        opts.on('--size N', Integer, 'Resources or concentrated actions (default: 8)') { |v| @options[:size] = v }
        opts.on('--resources N', Integer, 'Resource count for custom shape (default: 8)') { |v| @options[:resources] = v }
        opts.on('--actions N', Integer, 'Actions per resource for custom shape (default: 1)') { |v| @options[:actions] = v }
        opts.on('--samples N', Integer, 'Public samples per action (default: 1)') { |v| @options[:samples] = v }
        opts.on('--parameters N', Integer, 'Additional string parameters per action (default: 2)') { |v| @options[:parameters] = v }
        opts.on('--warmup N', Integer, 'Warmup batches per lane (default: 1)') { |v| @options[:warmup] = v }
        opts.on('--trials N', Integer, 'Measured batches per lane (default: 3)') { |v| @options[:trials] = v }
        opts.on('--iterations N', Integer, 'Derivations or adapter renders per batch (default: 100)') { |v| @options[:iterations] = v }
        opts.on('--lanes LIST', Array, 'context,html,rust (default: context,html)') { |v| @options[:lanes] = v }
        opts.on('--rust', 'Enable Rust profile and add the adapter lane; requires generator dependencies') do
          @options[:rust] = true
          @options[:lanes] |= ['rust']
        end
        opts.on('--user USER', %w[admin member], 'Synthetic documentation user (default: admin)') { |v| @options[:user] = v }
        opts.on('--source-root PATH', 'Load implementation from another checkout using this harness/fixture') do |v|
          @options[:source_root] = File.expand_path(v)
        end
        opts.on('--source-revision LABEL', 'Explicit source identity in addition to detected Git HEAD') { |v| @options[:source_revision] = v }
        opts.on('-h', '--help', 'Show options without loading dependencies') do
          puts opts
          exit
        end
      end
    end

    def validate_options
      %i[size resources actions samples parameters trials iterations].each do |name|
        raise OptionParser::InvalidArgument, "#{name} must be positive" unless @options.fetch(name) > 0
      end
      raise OptionParser::InvalidArgument, 'warmup must be nonnegative' if @options.fetch(:warmup) < 0
      unless @options[:lanes].any? && (@options[:lanes] - %w[context html rust]).empty?
        raise OptionParser::InvalidArgument, 'lanes must select context,html,rust'
      end

      @options[:lanes].uniq!
      @options[:rust] = true if @options[:lanes].include?('rust')
    end

    def shapes
      selected = @options[:shape] == 'both' ? %w[resources actions] : [@options[:shape]]
      selected.map do |shape|
        resources, actions = case shape
                             when 'resources' then [@options[:size], 1]
                             when 'actions' then [1, @options[:size]]
                             else @options.values_at(:resources, :actions)
                             end
        [shape, { resource_count: resources, actions_per_resource: actions,
                  samples_per_action: @options[:samples], parameters_per_action: @options[:parameters] }]
      end
    end

    def run_case(shape, dimensions)
      server, setup = measure { DocumentationPerformanceFixture.build(**dimensions, rust: @options[:rust]) }
      request = Rack::MockRequest.new(server.app)
      headers = { 'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64("#{@options[:user]}:fixture-only")}",
                  'HTTP_HOST' => 'example.test', 'HTTP_ACCEPT_LANGUAGE' => 'en', 'HTTP_ACCEPT' => 'text/html' }
      response = request.options(URL, **headers, 'HTTP_ACCEPT' => 'application/json')
      raise "OPTIONS returned #{response.status}" unless response.status == 200

      description = JSON.parse(response.body, symbolize_names: true).fetch(:response)
      profile = server.documentation_client_profiles(1)[:rust]
      parent = ClientExample::Context.new(version: 1, host: 'example.test',
                                          base_url: 'http://example.test/benchmark/api/', version_url: URL,
                                          description:, profile:)
      renderers = ClientExample.clients.select { |client| client.available?(parent) }.map(&:id)
      lanes = []
      if @options[:lanes].include?('context')
        replacement = Object.new.freeze
        sample = { request: { value: 0, enabled: false }, response: { value: '' } }
        { profile: { profile: replacement }, sample: { sample: } }.each do |name, changes|
          lanes << trial_lane("context_#{name}", @options[:iterations], ->(child) { context_output(child, parent) }) do
            child = nil
            @options[:iterations].times { child = parent.with(**changes) }
            child
          end
        end
      end
      if @options[:lanes].include?('html')
        if Server.method_defined?(:documentation_oauth)
          html_server, html_setup = measure { DocumentationPerformanceFixture.build(**dimensions, rust: @options[:rust], documentation_oauth: true) }
          html_request = Rack::MockRequest.new(html_server.app)
          html_url = "#{html_server.fixture_documentation_oauth.origin}/benchmark/api/v1/"
          html_headers = headers.except('HTTP_AUTHORIZATION')
          html_headers['HTTP_COOKIE'] = html_server.fixture_documentation_cookie(@options[:user])
        else
          html_request = request
          html_url = URL
          html_headers = headers
        end
        lanes << trial_lane('html', 1, ->(result) { html_output(result, dimensions) }) { html_request.get(html_url, **html_headers) }
      end
      lanes.concat(rust_lanes(parent, profile)) if @options[:lanes].include?('rust')
      { shape:, dimensions:, profile_mode: @options[:rust] ? 'rust' : 'dynamic', renderers:,
        description: body_identity(JSON.generate(description)), setup:, html_setup:, lanes: }
    end

    def rust_lanes(parent, profile)
      raise 'Rust profile is unavailable' unless profile

      resource = parent.description.fetch(:resources).fetch(:resource0)
      action = resource.fetch(:actions).fetch(:action0)
      context = parent.with(resource_path: ['resource0'], resource:, action_name: 'action0', action:,
                            sample: action.fetch(:examples).first)
      auth = parent.description.fetch(:authentication).fetch(:basic)
      %i[async blocking].flat_map do |mode|
        %i[example auth].map do |kind|
          trial_lane("rust_#{mode}_#{kind}", @options[:iterations], method(:rust_output)) do
            result = nil
            @options[:iterations].times do
              result = profile.adapter.render(kind:, context:, mode:, auth_method: :basic, auth_description: auth)
            end
            result
          end
        end
      end
    end

    def measure
      GC.start
      wall = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
      allocated = GC.stat(:total_allocated_objects)
      result = yield
      allocations = GC.stat(:total_allocated_objects) - allocated
      cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu
      wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall
      [result, { wall_seconds: wall, cpu_seconds: cpu, allocated_objects: allocations }]
    end

    def trial_lane(name, operations, summarize, &work)
      @options[:warmup].times { summarize.call(work.call) }
      trials = Array.new(@options[:trials]) do |index|
        result, metrics = measure(&work)
        { trial: index + 1, **metrics, output: summarize.call(result) }
      end
      outputs = trials.map { |trial| trial[:output] }.uniq
      raise "#{name} output changed between trials" unless outputs.length == 1

      median = METRICS.to_h do |metric|
        sorted = trials.map { |trial| trial.fetch(metric) }.sort
        middle = sorted.length / 2
        [metric, sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0]
      end
      { name:, operations_per_trial: operations, trials:, median: }
    end

    def body_identity(body)
      { body_bytes: body.bytesize, body_sha256: Digest::SHA256.hexdigest(body) }
    end

    def context_output(child, parent)
      { status: 'ok', description_shared: child.description.equal?(parent.description), frozen: child.frozen?,
        **body_identity(JSON.generate(description: child.description, sample: child.sample)) }
    end

    def html_output(response, dimensions)
      output = { status: response.status, **body_identity(response.body) }
      raise InvalidOutput.new('HTML request failed', output) unless response.status == 200

      body = response.body
      if body.match?(/\bdata-docs(?:\s|=|>)/)
        roots = body.scan(/<[^>]+\bdata-docs(?:\s|=|>)[^>]*>/)
        links = body.scan(/<a\b([^>]*\bdata-resource-directory-link[^>]*)>/).map do |attributes|
          attributes.first[/\bhref="([^"]*)"/, 1]
        end
        initialization = body.match(%r{<details\b[^>]*\bid="init-python-sync"[^>]*>(.*?)</details>}m)
        valid = roots.length == 1 && roots.first.scan(/\bdata-page="([^"]*)"/).flatten == ['overview'] && !links.empty? && links.all? { |href| href == '/benchmark/api/v1/?page=resources' } &&
                initialization && initialization[1].include?('<pre><code') &&
                !body.match?(/id="example-|PUBLIC_SAMPLE_|ADMIN_ONLY_(?:REQUEST|RESPONSE|DEFAULT)|admin_field/)
        raise InvalidOutput.new('HTML overview is incomplete or contains action data', output) unless valid
      elsif !body.include?('PUBLIC_SAMPLE_0') || !body.include?('init-examples')
        raise InvalidOutput.new('HTML request is missing sample panels', output)
      end
      output
    end

    def rust_output(result)
      unless result[:status] == :code && !result[:code].empty?
        raise InvalidOutput.new('Rust render failed', result)
      end

      { status: result[:status], **body_identity(result[:code]) }
    end

    def git(*)
      output, status = Open3.capture2('git', '-C', @options[:source_root], *, err: File::NULL)
      status.success? ? output.strip : nil
    end

    def source_identity
      { root: @options[:source_root], supplied_revision: @options[:source_revision],
        git_head: @git_head, git_status: git('status', '--porcelain', '--untracked-files=normal'),
        git_diff_sha256: git('diff', 'HEAD', '--binary')&.then { |diff| Digest::SHA256.hexdigest(diff) },
        loaded_source_sha256: $".grep(%r{/haveapi(?:/|\.rb)}).sort.to_h do |path|
          [path, Digest::SHA256.file(path).hexdigest]
        end }
    end

    def input_identity
      paths = [__FILE__, FIXTURE, File.join(ROOT, 'flake.lock'),
               ENV['BUNDLE_GEMFILE'] || File.join(ROOT, 'servers/ruby/Gemfile')]
      paths << "#{paths.last}.lock"
      paths << File.join(@options[:source_root], 'flake.lock')
      if @options[:rust]
        paths.concat(%w[clients/rust/Gemfile clients/rust/Gemfile.lock].map { |path| File.join(ROOT, path) })
      end
      { files_sha256: paths.select { |path| File.file?(path) }.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] },
        gem_paths: Gem.path,
        gems: Gem.loaded_specs.sort.to_h.transform_values { |spec| spec.version.to_s } }
    end
  end
end

if $0 == __FILE__
  begin
    puts JSON.pretty_generate(HaveAPI::DocumentationBenchmark.new(ARGV).run)
  rescue StandardError, LoadError => e
    puts JSON.pretty_generate(schema_version: 1, status: 'failed',
                              error: { class: e.class.name, message: e.message,
                                       output: e.respond_to?(:output) ? e.output : nil })
    warn "#{e.class}: #{e.message}"
    exit 1
  end
end
