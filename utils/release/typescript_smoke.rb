require 'rbconfig'
require_relative 'artifacts'

module HaveAPI
  module Release
    # Only the retained gems provide generator and shared schema code.
    class TypeScriptSmoke
      RUNTIME_VERSION = '0.30.2'.freeze
      RUNTIME_SHA256 = '96450c40a55ec7b7af4fca903d045bd0fc7ba1216efe12c3fee9b3e6a09e9198'.freeze

      def self.run(artifacts, directory, runtime)
        runtime = File.realpath(runtime)
        metadata = JSON.parse(File.read(File.join(runtime, 'package.json')))
        unless metadata.values_at('name', 'version') == ['haveapi-client', RUNTIME_VERSION] &&
               Digest::SHA256.file(File.join(runtime, 'dist/haveapi-client.js')).hexdigest == RUNTIME_SHA256
          raise Error, 'TypeScript smoke requires the prepared published haveapi-client 0.30.2 runtime'
        end

        package = Gem::Package.new(File.join(directory, "haveapi-typescript-client-#{artifacts.version}.gem"))
        shared_package = Gem::Package.new(File.join(directory, "haveapi-client-#{artifacts.version}.gem"))
        artifacts.inspect_typescript(package)
        artifacts.inspect_shared_schema(shared_package)
        unless shared_package.spec.name == 'haveapi-client' && shared_package.spec.version.to_s == artifacts.version
          raise Error, 'Wrong shared Ruby client gem identity'
        end

        env = ENV.keys.grep(/\ABUNDLE_/).to_h { |key| [key, nil] }.merge(
          'RUBYOPT' => nil, 'RUBYLIB' => nil, 'RUBYGEMS_GEMDEPS' => nil, 'NODE_PATH' => nil
        )
        identity = Release.capture(env, RbConfig.ruby, '--disable-gems',
                                   '-I', File.join(artifacts.root, 'clients/ruby/lib'),
                                   '-I', File.join(artifacts.root, 'clients/typescript/lib'),
                                   '-rhaveapi/typescript_client', '-e',
                                   'puts JSON.generate([HaveAPI::TypeScriptClient::Generator.source_digest, HaveAPI::Schema.source_identity])')
        compiler = File.join(artifacts.root, 'clients/js/node_modules/typescript/bin/tsc')
        Dir.mktmpdir('haveapi-typescript-smoke-') do |tmp|
          extracted = File.join(tmp, 'gem')
          shared = File.join(tmp, 'shared')
          package.extract_files(extracted)
          shared_package.extract_files(shared)
          Release.run(env, RbConfig.ruby, '--disable-gems', '-I', File.join(shared, 'lib'),
                      '-I', File.join(extracted, 'lib'), '-e', consumer,
                      extracted, shared, artifacts.version, identity, runtime, compiler, chdir: tmp)
        end
      end

      def self.consumer
        <<~'RUBY'
          require 'json'
          require 'fileutils'
          require 'open3'
          require 'rbconfig'
          require 'haveapi/typescript_client/cli'

          extracted, shared, version, identity, runtime, compiler = ARGV
          generator = HaveAPI::TypeScriptClient::Generator
          abort 'generator loaded outside extracted artifact' unless generator::ROOT == extracted
          abort 'wrong generator version' unless HaveAPI::TypeScriptClient::VERSION == version
          {'typescript_client' => extracted, 'schema' => shared, 'client/version' => shared}.each do |name, root|
            files = $LOADED_FEATURES.grep(%r{/haveapi/#{name}(?:/|\.rb)})
            unless !files.empty? && files.all? { |path| path.start_with?("#{root}/lib/") }
              abort 'source fallback outside extracted artifacts'
            end
          end
          expected = JSON.parse(identity)
          unless [generator.source_digest, HaveAPI::Schema.source_identity] == expected && expected.last.fetch('version') == version
            abort 'extracted source identity differs from candidate'
          end
          action = {
            'path' => '/mount/v1.0/widgets/{widget_id}', 'method' => 'GET', 'aliases' => [], 'auth' => false,
            'input' => nil,
            'output' => {'parameters' => {'name' => {'type' => 'String'}}, 'namespace' => 'widget', 'layout' => 'object'},
            'meta' => {'global' => nil, 'object' => nil}
          }
          snapshot = HaveAPI::Schema::Snapshot.from_description(
            api_version: '1.0', protocol_version: '2.0', source_url: 'https://schema.invalid/mount/v1.0/',
            mount_path: '/mount/', profile: 'release-smoke', description: {
              'help' => '/mount/v1.0/', 'meta' => {'namespace' => '_meta'}, 'authentication' => {},
              'resources' => {'widget' => {'resources' => {'part' => {'resources' => {}, 'actions' => {'show' => action}}}, 'actions' => {}}}
            }
          )
          File.write('schema.json', HaveAPI::Schema::Snapshot.canonical(snapshot))
          cli = File.join(extracted, 'bin/haveapi-typescript-client')
          args = %w[generate --schema schema.json --api-version 1.0 --output src/generated]
          [args, args + ['--check']].each do |arguments|
            unless system(RbConfig.ruby, '--disable-gems', '-I', File.join(shared, 'lib'), '-I', File.join(extracted, 'lib'), cli, *arguments)
              abort 'extracted TypeScript executable failed'
            end
          end
          manifest = JSON.parse(File.read('src/generated/.haveapi-generated.json'))
          abort 'wrong generated source identity' unless manifest.fetch('generator_source_sha256') == expected.first
          abort 'nested module missing' unless File.file?('src/generated/resources/widget/resources/part/actions/show.ts')
          FileUtils.mkdir_p('node_modules')
          File.symlink(runtime, 'node_modules/haveapi-client')
          File.write('package.json', JSON.generate(type: 'module', private: true))
          File.write('consumer.ts', <<~TS)
            import {AsyncClient} from 'haveapi-client';
            import {createClient} from './src/generated/index.js';
            const runtime = new AsyncClient('https://schema.invalid/mount/v1.0');
            const client = createClient({execute: spec => runtime.request(spec)});
            const call = () => client.widget.part.show({path: {widget_id: 1}});
            // @ts-expect-error Required path cannot be omitted.
            const invalid = () => client.widget.part.show({});
            void call; void invalid;
          TS
          config = {
            compilerOptions: {target: 'ES2022', module: 'NodeNext', moduleResolution: 'NodeNext',
              strict: true, exactOptionalPropertyTypes: true, noUncheckedIndexedAccess: true,
              verbatimModuleSyntax: true, types: [], lib: %w[ES2022 DOM], outDir: 'compiled'},
            include: ['consumer.ts', 'src/generated/**/*.ts']
          }
          File.write('tsconfig.json', JSON.generate(config))
          stdout, stderr, status = Open3.capture3('node', compiler, '-p', 'tsconfig.json', '--listFiles')
          abort "Packaged TypeScript consumer failed:\n#{stdout}#{stderr}" unless status.success?
          types = File.realpath(File.join(runtime, 'dist/types'))
          compiler_lib = File.realpath(File.join(File.dirname(compiler), '../lib'))
          allowed = [File.realpath('consumer.ts')] + Dir['src/generated/**/*.ts'].map { |path| File.realpath(path) }
          resolved = stdout.lines.map { |path| File.realpath(path.strip) }
          unless resolved.include?(File.join(types, 'haveapi.d.ts')) &&
                 resolved.all? { |path| allowed.include?(path) || path.start_with?("#{types}/", "#{compiler_lib}/") }
            abort 'consumer types resolved outside extracted consumer/runtime/compiler'
          end
          script = <<~JS
            import assert from 'node:assert/strict';
            import {createRequire} from 'node:module';
            import {realpathSync} from 'node:fs';
            import {createClient} from './compiled/src/generated/index.js';
            const require = createRequire(import.meta.url);
            const api = require('haveapi-client');
            assert.equal(realpathSync(require.resolve('haveapi-client')), realpathSync(process.argv[2]));
            assert.equal(api.Client.Version, '0.30.2');
            const runtime = new api.AsyncClient('https://schema.invalid/mount/v1.0');
            let request;
            runtime.request = async spec => { request = spec; return {data: {name: 'fixture'}}; };
            const client = createClient({execute: spec => runtime.request(spec)});
            const result = await client.widget.part.show({path: {widget_id: 7}});
            assert.equal(request.path, '/widgets/7');
            assert.equal(request.method, 'GET');
            assert.equal(result.data.name, 'fixture');
          JS
          File.write('consumer.mjs', script)
          abort 'packaged runtime adapter failed' unless system('node', 'consumer.mjs', File.join(runtime, 'dist/haveapi-client.js'))
          puts "Extracted TypeScript generator, shared schema and published runtime valid: #{version}"
        RUBY
      end
    end
  end
end

if $0 == __FILE__
  HaveAPI::Release::TypeScriptSmoke.run(
    HaveAPI::Release::Artifacts.new(File.expand_path('../..', __dir__)),
    File.expand_path(ARGV.fetch(0, 'dist')), File.expand_path(ARGV.fetch(1))
  )
end
