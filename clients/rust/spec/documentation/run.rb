ENV['BUNDLE_GEMFILE'] = File.expand_path('../../Gemfile', __dir__)
require 'bundler/setup'
require 'haveapi/rust_client/documentation'
require_relative '../integration/run'
require_relative 'cases'

server_lib = File.expand_path('../../../../servers/ruby/lib', __dir__)
$:.unshift(server_lib)
require 'haveapi/documentation_context'
require 'haveapi/client_examples/rust_client'

module RustDocumentationAcceptance
  module_function

  def command!(*args, env: {})
    raise "Acceptance command failed: #{args.join(' ')}" unless system(env, *args)
  end

  def source(renderer, kind, context, **)
    result = renderer.render(kind, context:, **)
    raise "Unexpected Rust documentation limitation: #{result[:reason]}" unless result[:status] == :code

    result.fetch(:code)
  end

  def profile_initializations(renderer, context, snapshot:, config:)
    documentation = HaveAPI::RustClient::Documentation
    # Installation metadata is inspected here; these programs compile against
    # the generated fixture below, not an installed or fetched Git repository.
    git = { git: 'https://example.test/documentation-fixture', rev: 'a' * 40 }
    variants = {
      'legacy_profile' => documentation.new(snapshot:, config:),
      'saved_profile' => documentation.from_snapshot(snapshot:, crate_name: config.fetch('crate_name')),
      'git_profile' => documentation.from_snapshot(snapshot:, crate_name: config.fetch('crate_name'), source: git),
      'git_versioned_profile' => documentation.from_snapshot(snapshot:, crate_name: config.fetch('crate_name'),
                                                             crate_version: config.fetch('crate_version'), source: git)
    }
    variants.transform_values do |adapter|
      profile = Struct.new(:language, :adapter).new(:rust, adapter.freeze).freeze
      source(renderer, :init, context.with(profile:))
    end
  end

  def write_examples(root, context, snapshot:, config:)
    examples = File.join(root, 'examples')
    FileUtils.mkdir_p(examples)
    names = []
    { async: HaveAPI::ClientExamples::RustAsyncClient, blocking: HaveAPI::ClientExamples::RustBlockingClient }.each do |mode, renderer|
      variants = { 'init' => source(renderer, :init, context) }
      variants.merge!(profile_initializations(renderer, context, snapshot:, config:))
      index = nil
      RustDocumentationCases.cases.each do |entry|
        current = RustDocumentationCases.context_for(context, entry)
        rendered = source(renderer, :example, current)
        checked = RustDocumentationCases.assert_output(rendered, entry[:assertion])
        variants[entry.fetch(:name)] = checked
        index = checked if entry.fetch(:name) == 'index'
      end
      %w[basic token oauth2].each do |provider|
        auth = source(renderer, :auth, context, auth_method: provider.to_sym,
                                                auth_description: context.description.fetch('authentication').fetch(provider))
        variants["auth_#{provider}"] = RustDocumentationCases.compose_authentication(auth, index)
      end
      variants.each do |name, rendered|
        example_name = "#{mode}_#{name}"
        File.write(File.join(examples, "#{example_name}.rs"), rendered)
        names << example_name
      end
    end
    names
  end

  def tool_identity(executable, *arguments)
    path = if executable.include?(File::SEPARATOR)
             File.realpath(executable)
           else
             ENV.fetch('PATH').split(File::PATH_SEPARATOR).filter_map do |directory|
               candidate = File.join(directory, executable)
               File.realpath(candidate) if File.file?(candidate) && File.executable?(candidate)
             end.first
           end
    raise "Tool executable not found: #{executable}" unless path

    output, status = Open3.capture2e(executable, *arguments)
    raise "Tool identity probe failed: #{executable}" unless status.success?

    { 'executable' => path, 'arguments' => arguments, 'version' => output.strip }
  end

  def evidence_directory(directory, mount)
    return unless directory

    FileUtils.mkdir_p(directory)
    destination = File.join(directory, mount == '/' ? 'root' : 'mounted-api')
    Dir.mkdir(destination)
    destination
  end

  def retain_evidence(root:, destination:, snapshot:, config:, tools:)
    return unless destination

    File.write(File.join(destination, 'tools.json'), "#{JSON.pretty_generate(tools)}\n")
    if snapshot
      File.write(File.join(destination, 'snapshot.json'), HaveAPI::RustClient::Snapshot.canonical(snapshot))
    end
    if config
      File.write(File.join(destination, 'generator.toml'), config.map { |key, value| "#{key} = #{JSON.generate(value)}\n" }.join)
    end
    %w[Cargo.toml Cargo.lock src examples].each do |name|
      path = File.join(root, name)
      FileUtils.cp_r(path, destination) if File.exist?(path)
    end
  end

  def run
    abort 'Set HAVEAPI_RUST_DOCUMENTATION=1 to run rendered Rust acceptance' unless ENV['HAVEAPI_RUST_DOCUMENTATION'] == '1'
    if %w[RUSTC RUSTC_WRAPPER RUSTC_WORKSPACE_WRAPPER].any? { |key| !ENV.fetch(key, '').empty? }
      raise 'Unset inherited compiler overrides before testing the development and MSRV toolchains'
    end

    msrv_cargo = ENV.fetch('HAVEAPI_RUST_MSRV_CARGO')
    rustc = ENV.fetch('HAVEAPI_RUST_MSRV_RUSTC')
    stdout, status = Open3.capture2(rustc, '--version')
    raise 'Rust documentation MSRV compiler must be 1.95' unless status.success? && stdout.start_with?('rustc 1.95.')

    evidence = ENV.fetch('HAVEAPI_RUST_DOCUMENTATION_EVIDENCE', nil)
    tools = if evidence
              {
                'generator_version' => HaveAPI::RustClient::VERSION,
                'development_cargo' => tool_identity('cargo', '--version', '--verbose'),
                'development_rustc' => tool_identity('rustc', '--version', '--verbose'),
                'generation_rustfmt' => tool_identity(ENV.fetch('RUSTFMT', 'rustfmt'), '--version'),
                'msrv_cargo' => tool_identity(msrv_cargo, '--version', '--verbose'),
                'msrv_rustc' => tool_identity(rustc, '--version', '--verbose')
              }
            end
    Dir.mktmpdir('haveapi-rust-documentation-') do |temporary|
      ['/', '/mounted/api/'].each do |mount|
        destination = snapshot = config = nil
        root = File.join(temporary, mount == '/' ? 'root' : 'mounted-api')
        FileUtils.mkdir_p(root)
        destination = evidence_directory(evidence, mount)
        RustClientIntegration.with_server(mount) do |base_url|
          snapshot = HaveAPI::RustClient::Snapshot.fetch(url: "#{base_url}v1.0/", api_version: '1.0', profile: 'documentation-fixture')
          config = {
            'crate_name' => 'haveapi-documentation-fixture', 'crate_version' => '0.1.0', 'license' => 'MIT',
            'edition' => '2024', 'rust_version' => '1.95',
            'rustfmt_version' => IO.popen(%w[rustfmt --version], &:read).strip
          }
          generator = HaveAPI::RustClient::Generator.new(schema: snapshot, config:)
          FileUtils.mkdir_p(File.join(root, 'src'))
          File.write(File.join(root, 'src/lib.rs'), "mod generated;\npub use generated::*;\n")
          File.write(File.join(root, 'Cargo.toml'), generator.manifest_requirements)
          generator.generate(output: File.join(root, 'src/generated'))
          adapter = HaveAPI::RustClient::Documentation.from_description(
            description: snapshot.fetch('description'), api_version: '1.0', protocol_version: '2.0', mount_path: mount,
            crate_name: config.fetch('crate_name')
          ).freeze
          profile = Struct.new(:language, :package_name, :package_version, :adapter).new(
            :rust, config.fetch('crate_name'), nil, adapter
          ).freeze
          context = HaveAPI::ClientExample::Context.new(
            version: '1.0', host: '127.0.0.1', base_url:, version_url: "#{base_url}v1.0/",
            description: snapshot.fetch('description'), profile:
          )
          names = write_examples(root, context, snapshot:, config:)
          env = { 'HAVEAPI_BASE_URL' => base_url, 'HAVEAPI_USER' => 'admin', 'HAVEAPI_PASSWORD' => 'pass',
                  'HAVEAPI_TOKEN' => 'oauth-user' }
          # Obtain the deterministic existing token through the real fixture's
          # API, rather than seeding private server state or using real secrets.
          token_snapshot = snapshot.fetch('description').fetch('authentication').fetch('token')
          token_resource = token_snapshot.fetch('resources').values.first
          token_action = token_resource.fetch('actions').find { |name, _value| name.casecmp?('request') }.last
          request = { token_action.fetch('input').fetch('namespace') => { user: 'admin', password: 'pass', lifetime: 'fixed' } }
          response = Net::HTTP.post(URI("#{base_url.delete_suffix(mount)}#{token_action.fetch('path')}"),
                                    JSON.generate(request),
                                    'Content-Type' => 'application/json')
          envelope = JSON.parse(response.body)
          raise 'Fixture token acquisition failed' unless envelope['status'] == true

          token = envelope.fetch('response').fetch(token_action.fetch('output').fetch('namespace')).fetch('token')
          command!('cargo', 'generate-lockfile', '--manifest-path', File.join(root, 'Cargo.toml'))
          [['cargo', {}], [msrv_cargo, { 'RUSTC' => rustc }]].each do |cargo, compiler_env|
            command!(cargo, 'check', '--locked', '--manifest-path', File.join(root, 'Cargo.toml'), '--all-features', '--examples',
                     env: compiler_env)
            names.each do |name|
              selected_env = env.merge('HAVEAPI_TOKEN' => name.end_with?('auth_token') ? token : 'oauth-user').merge(compiler_env)
              command!(cargo, 'run', '--locked', '--quiet', '--manifest-path', File.join(root, 'Cargo.toml'),
                       '--all-features', '--example', name, env: selected_env)
            end
          end
          $stdout.puts "Rendered Rust async/blocking/MSRV acceptance passed at #{mount} (#{names.length} programs)"
        end
      ensure
        retain_evidence(root:, destination:, snapshot:, config:, tools:)
      end
    end
  end
end

RustDocumentationAcceptance.run if $0 == __FILE__
