require 'rbconfig'
require_relative 'artifacts'

module HaveAPI
  module Release
    # Only the extracted gem supplies generator code, templates and runtime.
    # Its third-party Ruby dependencies come from the prepared component bundle.
    class RustSmoke
      def self.run(artifacts, directory)
        package = Gem::Package.new(File.join(directory, "haveapi-rust-client-#{artifacts.version}.gem"))
        artifacts.inspect_rust(package)
        Dir.mktmpdir('haveapi-rust-smoke-') do |tmp|
          extracted = File.join(tmp, 'gem')
          package.extract_files(extracted)
          env = ENV.keys.grep(/\ABUNDLE_/).to_h { |key| [key, nil] }.merge(
            'GEM_HOME' => File.join(artifacts.root, 'clients/rust/.gems'),
            'GEM_PATH' => [File.join(artifacts.root, 'clients/rust/.gems'), Gem.default_dir].join(File::PATH_SEPARATOR),
            'RUBYOPT' => nil, 'RUBYLIB' => nil
          )
          Release.run(env, RbConfig.ruby, '-I', File.join(extracted, 'lib'), '-e', consumer,
                      extracted, artifacts.version, chdir: tmp)
        end
      end

      def self.consumer
        <<~'RUBY'
          require 'json'
          require 'open3'
          require 'rbconfig'
          require 'haveapi/rust_client/cli'

          extracted, version = ARGV
          generator = HaveAPI::RustClient::Generator
          abort 'generator loaded outside the extracted artifact' unless generator::ROOT == extracted
          abort 'wrong installed generator version' unless HaveAPI::RustClient::VERSION == version
          unless $LOADED_FEATURES.grep(%r{/haveapi/rust_client(?:/|\.rb)}).all? { |path| path.start_with?("#{extracted}/lib/") }
            abort 'generator source fallback outside the extracted artifact'
          end
          snapshot = HaveAPI::RustClient::Snapshot.from_description(
            api_version: '1.0', protocol_version: '2.0', source_url: 'https://example.test/v1.0/',
            profile: 'release-smoke', description: {
              'help' => '/v1.0/', 'meta' => { 'namespace' => '_meta' }, 'authentication' => {},
              'resources' => { 'widget' => { 'resources' => {}, 'actions' => { 'show' => {
                'path' => '/v1.0/widgets/{widget_id}', 'method' => 'GET', 'aliases' => [], 'auth' => false,
                'input' => { 'parameters' => {}, 'namespace' => 'widget', 'layout' => 'object' },
                'output' => { 'parameters' => { 'name' => { 'type' => 'String' } }, 'namespace' => 'widget', 'layout' => 'object' },
                'meta' => { 'global' => nil, 'object' => nil }
              } } } }
            }
          )
          File.write('schema.json', HaveAPI::RustClient::Snapshot.canonical(snapshot))
          formatter, stderr, status = Open3.capture3('rustfmt', '--version')
          abort stderr unless status.success?
          config = {
            'crate_name' => 'haveapi-release-smoke', 'crate_version' => '0.1.0', 'license' => 'MIT',
            'edition' => '2024', 'rust_version' => '1.95', 'rustfmt_version' => formatter.strip
          }
          File.write('generator.toml', config.map { |key, value| "#{key} = #{value.to_json}" }.join("\n"))
          args = %w[generate --schema schema.json --api-version 1.0 --config generator.toml --output generated]
          cli = File.join(extracted, 'bin/haveapi-rust-client')
          [args, args + ['--check']].each do |arguments|
            abort 'extracted generator executable failed' unless system(RbConfig.ruby, '-I', File.join(extracted, 'lib'), cli, *arguments)
          end
          runtime = File.join(extracted, 'runtime/src/runtime')
          Dir.glob("#{runtime}/**/*").select { |path| File.file?(path) }.each do |path|
            copied = File.join('generated/runtime', path.delete_prefix("#{runtime}/"))
            abort "wrong copied runtime: #{copied}" unless File.binread(copied) == File.binread(path)
          end
          abort 'generated action missing' unless File.file?('generated/resources/widget/show.rs')
          puts "Extracted Rust generator and runtime valid: #{version}"
        RUBY
      end
    end
  end
end

if $0 == __FILE__
  HaveAPI::Release::RustSmoke.run(HaveAPI::Release::Artifacts.new(File.expand_path('../..', __dir__)), File.expand_path(ARGV.fetch(0, 'dist')))
end
