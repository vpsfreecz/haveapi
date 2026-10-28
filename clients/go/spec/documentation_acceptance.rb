# Run after committed-deliverable review; this generates, compiles and executes SDKs.
require 'json'
require 'open3'
require 'tmpdir'
require 'tempfile'
require 'webrick'

require 'haveapi/go_client/documentation'
require 'haveapi/documentation_clients'
require 'haveapi/client_examples/go_client'
require_relative 'support/documentation_fixture'

class GoDocumentationAcceptance
  def self.build_command(destination)
    # The disposable consumer has no source history to stamp into its binaries.
    ['go', 'build', '-buildvcs=false', '-o', destination, './cmd/...']
  end

  def self.expected_cases
    # The SDK emits an empty metadata envelope for this metadata-bearing action.
    object_body = { 'widget' => { 'name' => nil, 'enabled' => false, 'count' => 0 }, '_meta' => {} }
    {
      init: {}, basic: {}, token: {}, oauth2: {},
      object: { body: object_body, output: '123' },
      empty: { body: { 'widget' => {} } }, omitted: { body: { 'widget' => {} } },
      list: { output: "1\n2" }, fail: { output: 'fixture failure' },
      association: { output: '9' },
      # The SDK encodes false/true query booleans as 0/1.
      query: { query: { 'widget[name]' => '', 'widget[enabled]' => '0', 'widget[count]' => '0' } },
      operation: { state: true },
      basic_call: { body: object_body, auth: { authorization: "Basic #{['fixture-user:fixture-password'].pack('m0')}" } },
      token_call: { body: object_body, auth: { token: 'fixture-token' } },
      oauth2_call: { body: object_body, auth: { oauth2: 'fixture-access-token' } },
      hostile: { body: { 'widget' => { 'name' => "quote\"\\\n雪</script>" }, '_meta' => {} }, output: '123' }
    }
  end

  def self.run!
    check_environment!
    new.run!
  end

  # The same optional gems must be visible to Bundler and the product loader.
  # This preflight performs no generation, compilation or server startup.
  def self.check_environment!
    %w[haveapi haveapi-go-client].each do |name|
      raise "#{name} is absent from the acceptance bundle" unless Gem.loaded_specs.has_key?(name)
    end
    unless Gem.loaded_specs.fetch('haveapi-go-client').version.to_s == HaveAPI::GoClient::VERSION
      raise 'activated Go generator specification does not match its loaded version'
    end

    Tempfile.create(['haveapi-go-documentation-profile-', '.json']) do |file|
      file.write(JSON.generate(GoDocumentationFixture.description))
      file.flush
      profiles = HaveAPI::ClientExample::Profiles.new
      profiles.register('7', go: {
        import_path: 'example.test/sdk/client', module_version: 'v1.2.3', description_path: file.path,
        generator_version: Gem.loaded_specs.fetch('haveapi-go-client').version.to_s
      })
      profiles.mount(['7'])
      profiles.finalize(nil)
      raise 'configured Go profile is unavailable' unless profiles.for_version('7').fetch(:go).language == :go
    end
  end

  def initialize
    @requests = Queue.new
    @server = WEBrick::HTTPServer.new(
      BindAddress: '127.0.0.1', Port: 0, AccessLog: [], Logger: WEBrick::Log.new(File::NULL)
    )
    @server.mount_proc('/') { |request, response| serve(request, response) }
  end

  def run!
    thread = Thread.new { @server.start }
    Dir.mktmpdir('haveapi-go-documentation-') do |dir|
      prepare_sdk(dir)
      prepare_programs(dir)
      command('gofmt', '-w', File.join(dir, 'consumer'))
      command(*self.class.build_command(File.join(dir, 'bin')), chdir: File.join(dir, 'consumer'))
      @cases.each do |name, expected|
        stdout = command(File.join(dir, 'bin', name.to_s), env: {
          'HAVEAPI_USER' => 'fixture-user', 'HAVEAPI_PASSWORD' => 'fixture-password',
          'HAVEAPI_TOKEN' => 'fixture-token', 'HAVEAPI_ACCESS_TOKEN' => 'fixture-access-token'
        })
        verify(name, expected, stdout)
      end
    end
    # This is a standalone acceptance runner, not an RSpec example.
    $stdout.write("Go documentation acceptance: #{@cases.length} rendered programs compiled and executed\n") # rubocop:disable RSpec/Output
  ensure
    @server.shutdown
    thread&.join
  end

  private

  def prepare_sdk(dir)
    @description = GoDocumentationFixture.description
    @description[:resources][:client][:resources][:child][:actions].merge!(
      empty: GoDocumentationFixture.action(path: '/mounted/v7/empty', input: input),
      omitted: GoDocumentationFixture.action(path: '/mounted/v7/omitted', input: input),
      list: GoDocumentationFixture.action(path: '/mounted/v7/list', method: 'GET', output: output(layout: 'hash_list')),
      association: GoDocumentationFixture.action(
        path: '/mounted/v7/association', method: 'GET',
        output: GoDocumentationFixture.io({ owner: { type: 'Resource', resource: ['owner'], value_id: 'id', value_label: 'label' } })
      ),
      fail: GoDocumentationFixture.action(path: '/mounted/v7/fail', method: 'GET'),
      query: GoDocumentationFixture.action(path: '/mounted/v7/query', method: 'GET', input: input),
      operation: GoDocumentationFixture.action(
        path: '/mounted/v7/operation', method: 'GET', blocking: true,
        meta: { global: { output: GoDocumentationFixture.io({ action_state_id: { type: 'Integer' } }, namespace: false) } }
      )
    )
    # This exact local JSON is both generator input and the configured profile.
    description_path = File.join(dir, 'sdk-description.json')
    File.write(description_path, JSON.pretty_generate(@description))
    saved = JSON.parse(File.read(description_path), symbolize_names: true)
    generator = HaveAPI::GoClient::Generator.from_description(saved, File.join(dir, 'sdk'),
                                                              module: 'example.test/sdk', package: 'client')
    generator.generate
    profiles = HaveAPI::ClientExample::Profiles.new
    profiles.register('7', go: {
      import_path: 'example.test/sdk/client', module_version: 'v1.2.3', description_path:,
      generator_version: HaveAPI::GoClient::VERSION
    })
    profiles.mount(['7'])
    profiles.finalize(nil)
    @profile = profiles.for_version('7').fetch(:go)
    FileUtils.mkdir_p(File.join(dir, 'consumer'))
    FileUtils.mkdir_p(File.join(dir, 'bin'))
    File.write(File.join(dir, 'consumer/go.mod'), <<~MOD)
      module example.test/documentation-consumer

      go 1.20

      require example.test/sdk v1.2.3
      replace example.test/sdk => ../sdk
    MOD
  end

  def prepare_programs(dir)
    @cases = self.class.expected_cases.flat_map do |name, expected|
      %i[simple thorough].map { |detail| ["#{detail}_#{name}", expected.merge(case_name: name, detail:)] }
    end.to_h
    @cases.each do |program_name, expected|
      name, detail = expected.values_at(:case_name, :detail)
      kind = if name == :init
               :init
             else
               (%i[basic token oauth2].include?(name) ? :auth : :example)
             end
      action_name = %i[object basic_call token_call oauth2_call hostile].include?(name) ? :client : name
      action = @description.dig(:resources, :client, :resources, :child, :actions, action_name)
      sample = case name
               when :object, :basic_call, :token_call, :oauth2_call then GoDocumentationFixture.sample
               when :hostile then GoDocumentationFixture.sample.merge(request: { name: "quote\"\\\n雪</script>" })
               when :empty then { request: {}, response: {}, status: true }
               when :omitted then { response: {}, status: true }
               when :list then { response: [{ id: 1 }, { id: 2 }], status: true }
               when :association then { response: { owner: { id: 9 } }, status: true }
               when :fail then { status: false }
               when :query then { request: { name: nil, enabled: false, count: 0 }, status: true }
               else { status: true }
               end
      context = HaveAPI::ClientExample::Context.new(
        detail:,
        version: '7', host: '127.0.0.1', base_url: "http://127.0.0.1:#{@server.config[:Port]}/mounted/",
        version_url: "http://127.0.0.1:#{@server.config[:Port]}/mounted/v7/", description: @description,
        resource_path: %w[client child], action_name:, action:, sample:, profile: @profile
      )
      result = HaveAPI::ClientExamples::GoClient.render(kind, context:, auth_method: name, auth_description: {})
      raise "#{name}: unexpected limitation: #{result[:reason]}" unless result[:status] == :code

      path = File.join(dir, 'consumer/cmd', program_name)
      FileUtils.mkdir_p(path)
      # Simple fragments use the separately rendered setup; requests stay intact.
      source = result.fetch(:code)
      if detail == :simple && kind == :example
        setup = if name.to_s.end_with?('_call')
                  HaveAPI::ClientExamples::GoClient.render(:auth, context:, auth_method: name.to_s.delete_suffix('_call').to_sym, auth_description: {})
                else
                  HaveAPI::ClientExamples::GoClient.render(:init, context:)
                end
        raise "#{name}: setup limitation" unless setup[:status] == :code

        source = compose_fragment(setup.fetch(:code), source)
      elsif name.to_s.end_with?('_call')
        auth = HaveAPI::ClientExamples::GoClient.render(:auth, context:, auth_method: name.to_s.delete_suffix('_call').to_sym, auth_description: {})
        raise "#{name}: authentication limitation" unless auth[:status] == :code

        source = compose(auth.fetch(:code), source)
      end
      File.write(File.join(path, 'main.go'), source)
    end
  end

  def input
    GoDocumentationFixture.io({ name: { type: 'String', nullable: true }, enabled: { type: 'Boolean' },
                                count: { type: 'Integer' }, unused: { type: 'String' } })
  end

  def output(layout: 'hash')
    GoDocumentationFixture.io({ id: { type: 'Integer' }, name: { type: 'String', nullable: true } }, layout:)
  end

  def serve(request, response)
    @requests << { path: request.path, query: request.query, raw_query: request.query_string, body: request.body,
                   auth: { authorization: request['Authorization'], token: request['X-Token'], oauth2: request['X-OAuth'] } }
    response['Content-Type'] = 'application/json'
    result = case request.path
             when '/mounted/v7/fail'
               { status: false, message: 'fixture failure', errors: { name: ['invalid'] } }
             when '/mounted/v7/list'
               { status: true, response: { widget: [{ id: 1 }, { id: 2 }] } }
             when '/mounted/v7/association'
               { status: true, response: { widget: { owner: { id: 9 } } } }
             when '/mounted/v7/operation'
               { status: true, response: { _meta: { action_state_id: 55 } } }
             when '/mounted/v7/action_states/55'
               { status: true, response: { action_state: { id: 55 } } }
             else
               { status: true, response: { widget: { id: 123 } } }
             end
    response.body = JSON.generate(result)
  end

  def verify(_program_name, expected, stdout)
    name = expected.fetch(:case_name)
    if %i[init basic token oauth2].include?(name)
      raise "#{name}: initialization performed a request" unless @requests.empty?

      return
    end

    request = @requests.pop(true)
    expected_path = %i[object basic_call token_call oauth2_call hostile].include?(name) ? '/mounted/v7/clients/42/children/a/b' : "/mounted/v7/#{name}"
    raise "#{name}: unexpected mounted/versioned path #{request[:path]}" unless request[:path] == expected_path
    if expected[:body] && JSON.parse(request[:body]) != expected[:body]
      raise "#{name}: supplied input or omission was not preserved: #{request[:body]}"
    end

    if expected[:query] && request[:query] != expected[:query]
      raise "#{name}: query values were not preserved: expected #{expected[:query].inspect}, " \
            "got #{request[:query].inspect}; raw query #{request[:raw_query].inspect}"
    end

    if expected[:auth] && !expected[:auth].all? { |key, value| request[:auth][key] == value }
      raise "#{name}: rendered authentication did not reach the fixture"
    end
    raise "#{name}: unexpected rendered output #{stdout.inspect}" if expected[:output] && !stdout.include?(expected[:output])

    if expected[:state] && expected[:detail] == :thorough
      state = @requests.pop(true)
      raise 'operation: generated helper used the wrong route' unless state[:path] == '/mounted/v7/action_states/55'
    end
    raise "#{name}: unexpected extra request" unless @requests.empty?
  end

  def compose_fragment(setup, fragment)
    raise 'rendered initialization marker missing' unless setup.include?('  _ = api') || setup.include?('api.Set')

    # fmt is used by the exact fragment's error/output handling.
    setup.sub("import (\n", "import (\n  \"fmt\"\n").sub(/\n\}\n\z/) { "\n#{fragment}}\n" }
  end

  # Compose exact rendered sections, deduplicating their shared initialization.
  def compose(auth, action)
    imports = [auth, action].flat_map { |source| source.match(/^import \(\n(.*?)\n\)/m)[1].lines(chomp: true) }.uniq
    auth_body = auth.match(/^func main\(\) \{\n(.*)\n\}\n/m)[1].lines
    action_body = action.match(/^func main\(\) \{\n(.*)\n\}\n/m)[1].lines
    raise 'rendered initialization differs across sections' unless auth_body.first == action_body.first

    [auth.split('import (', 2).first, "import (\n", imports.join("\n"), "\n)\n\nfunc main() {\n",
     auth_body.join, "\n", action_body.drop(1).join, "\n}\n"].join
  end

  def command(*args, chdir: nil, env: {})
    environment = { 'GOWORK' => 'off', 'GOPROXY' => 'off', 'GOSUMDB' => 'off', 'GOTOOLCHAIN' => 'local' }.merge(env)
    stdout, stderr, status = Open3.capture3(environment, *args, **(chdir ? { chdir: } : {}))
    raise "#{args.first} failed: #{stdout}\n#{stderr}" unless status.success?

    stdout
  end
end

if $0 == __FILE__
  case ARGV
  when [] then GoDocumentationAcceptance.run!
  when ['--check-environment'] then GoDocumentationAcceptance.check_environment!
  else raise ArgumentError, 'usage: documentation_acceptance.rb [--check-environment]'
  end
end
