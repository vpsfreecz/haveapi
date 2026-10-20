require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rubygems/package'
require 'tmpdir'
require 'zlib'

module HaveAPI
  module Release
    class Error < StandardError; end

    # The package names and their order are the maintained publication contract.
    GEMS = {
      'haveapi-client' => 'clients/ruby',
      'haveapi' => 'servers/ruby',
      'haveapi-go-client' => 'clients/go'
    }.freeze
    REPOSITORY = 'vpsfreecz/haveapi'.freeze
    PHP_REPOSITORY = 'git@github.com:vpsfreecz/haveapi-client-php.git'.freeze

    def self.capture(*command, chdir: Dir.pwd)
      stdout, stderr, status = Open3.capture3(*command, chdir:)
      raise Error, "#{command.first} failed: #{stderr.strip}" unless status.success?

      stdout
    end

    def self.run(*command, chdir: Dir.pwd)
      raise Error, "#{command.first} failed" unless system(*command, chdir:)
    end

    class Artifacts
      attr_reader :root, :version

      def initialize(root)
        @root = File.expand_path(root)
        @version = File.read(File.join(root, 'VERSION')).strip
        raise Error, 'VERSION must be X.Y.Z' unless version.match?(/\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/)
      end

      def source
        Release.capture('git', 'rev-parse', 'HEAD', chdir: root).strip
      end

      def tag
        "v#{version}"
      end

      def names
        GEMS.keys.map { |name| "#{name}-#{version}.gem" } + [
          "haveapi-client-#{version}.tgz", 'haveapi-client.js',
          "haveapi-client-php-#{version}.tar", 'release-notes.md'
        ] + python_names
      end

      def python_names
        ["haveapi_client-#{version}-py3-none-any.whl", "haveapi_client-#{version}.tar.gz"]
      end

      def notes
        changelog = File.read(File.join(root, 'CHANGELOG.md'))
        sections = changelog.split(/(?=^# )/)
        section = sections.find { |s| s.lines.first.match?(/ - version #{Regexp.escape(version)}\s*$/) }
        raise Error, "CHANGELOG.md has no entry for #{version}" unless section && section.include?('## ')

        "#{section.strip}\n"
      end

      def check(clean: false, release_tag: nil)
        paths = {
          'servers/ruby/lib/haveapi/version.rb' => /\bVERSION = '([^']+)'/,
          'clients/ruby/lib/haveapi/client/version.rb' => /\bVERSION = '([^']+)'/,
          'clients/go/lib/haveapi/go_client/version.rb' => /\bVERSION = '([^']+)'/,
          'clients/js/src/haveapi/client.ts' => /Client\.Version = '([^']+)'/,
          'clients/php/src/Client.php' => /const VERSION = '([^']+)'/,
          'clients/python/pyproject.toml' => /^version = "([^"]+)"/
        }
        paths.each do |path, pattern|
          actual = File.read(File.join(root, path)).match(pattern)&.captures&.first
          raise Error, "Version mismatch in #{path}" unless actual == version
        end
        %w[clients/js/package.json clients/php/composer.json].each do |path|
          raise Error, "Version mismatch in #{path}" unless JSON.parse(File.read(File.join(root, path))).fetch('version') == version
        end
        lock = JSON.parse(File.read(File.join(root, 'clients/js/package-lock.json')))
        unless [lock, lock.fetch('packages').fetch('')].all? { |entry| entry.values_at('name', 'version') == ['haveapi-client', version] }
          raise Error, 'Identity or version mismatch in clients/js/package-lock.json'
        end

        %w[servers/ruby/haveapi.gemspec clients/go/haveapi-go-client.gemspec].each do |path|
          dependency = File.read(File.join(root, path)).match(/add_dependency 'haveapi-client', '([^']+)'/)
          raise Error, "Dependency mismatch in #{path}" unless dependency && dependency[1] == "~> #{version}"
        end
        notes
        if clean && !Release.capture('git', 'status', '--porcelain', '--untracked-files=no', chdir: root).empty?
          raise Error, 'Release builds require a clean tracked checkout'
        end

        check_tag(release_tag) if release_tag
      end

      def check_tag(release_tag)
        raise Error, "Tag must be #{tag}" unless release_tag == tag
        raise Error, 'Tag no longer points to this source commit' unless Release.capture('git', 'rev-parse', "#{tag}^{commit}", chdir: root).strip == source

        refs = Release.capture('git', 'ls-remote', 'origin', "refs/tags/#{tag}", "refs/tags/#{tag}^{}", chdir: root).lines.to_h do |ref|
          sha, name = ref.split
          [name, sha]
        end
        remote = refs["refs/tags/#{tag}^{}"] || refs["refs/tags/#{tag}"]
        raise Error, 'Remote tag is missing or has moved' unless remote == source

        line = version.split('.').first(2).join('.')
        branches = Release.capture('git', 'for-each-ref', '--format=%(refname:short)', 'refs/remotes/origin', chdir: root).lines.filter_map do |ref|
          ref.strip.match(%r{\Aorigin/haveapi-(\d+\.\d+)\z})&.captures&.first
        end
        latest = branches.max_by { |v| Gem::Version.new(v) }
        raise Error, 'Tag must belong to the newest release branch' unless line == latest

        Release.capture('git', 'merge-base', '--is-ancestor', source, "origin/haveapi-#{line}", chdir: root)
      end

      def write_manifest(directory)
        directory = File.expand_path(directory)
        File.write(File.join(directory, 'release-notes.md'), notes)
        inspect_packages(directory)
        files = names.to_h { |name| [name, Digest::SHA256.file(File.join(directory, name)).hexdigest] }
        tools = %w[ruby gem node npm go php composer python uv].to_h do |tool|
          flag = tool == 'go' ? 'version' : '--version'
          [tool, Release.capture(tool, flag).strip]
        end
        lock_paths = %w[Gemfile.lock servers/ruby/Gemfile.lock clients/ruby/Gemfile.lock clients/go/Gemfile.lock clients/js/package-lock.json clients/php/composer.lock clients/python/uv.lock]
        dependency_locks = lock_paths.to_h { |path| [path, File.read(File.join(root, path))] }
        manifest = { schema: 1, source:, version:, tag:, run_id: ENV.fetch('GITHUB_RUN_ID', 'local'), files:, tools:, dependency_locks: }
        File.write(File.join(directory, 'release-manifest.json'), "#{JSON.pretty_generate(manifest)}\n")
      end

      def verify(directory)
        directory = File.expand_path(directory)
        manifest = JSON.parse(File.read(File.join(directory, 'release-manifest.json')))
        unless manifest.values_at('schema', 'source', 'version', 'tag') == [1, source, version, tag]
          raise Error, 'Manifest does not describe this source/version'
        end
        if ENV['GITHUB_RUN_ID'] && manifest.fetch('run_id') != ENV.fetch('GITHUB_RUN_ID')
          raise Error, 'Artifacts belong to a different workflow run'
        end
        raise Error, 'Unexpected artifact set' unless manifest.fetch('files').keys.sort == names.sort

        manifest.fetch('files').each do |name, digest|
          path = File.join(directory, name)
          raise Error, "Artifact checksum mismatch: #{name}" unless File.file?(path) && !File.symlink?(path) && Digest::SHA256.file(path).hexdigest == digest
        end
        inspect_packages(directory)
        manifest
      end

      def tar_files(path, gzip: false)
        files = {}
        File.open(path, 'rb') do |file|
          stream = gzip ? Zlib::GzipReader.new(file) : file
          Gem::Package::TarReader.new(stream) do |tar|
            tar.each do |entry|
              name = entry.full_name
              raise Error, "Unsafe archive entry: #{name}" if name.start_with?('/') || name.split('/').include?('..')
              next if entry.directory?

              raise Error, "Unsupported archive entry: #{name}" unless entry.file?
              raise Error, "Duplicate archive entry: #{name}" if files.has_key?(name)

              mode = entry.header.mode.nobits?(0o111) ? 0o644 : 0o755
              files[name] = [entry.read, mode]
            end
          end
        end
        files
      end

      def inspect_packages(directory)
        GEMS.each_key do |name|
          package = Gem::Package.new(File.join(directory, "#{name}-#{version}.gem"))
          spec = package.spec
          raise Error, "Wrong gem identity: #{name}" unless spec.name == name && spec.version.to_s == version
          next if name == 'haveapi-client'

          dependency = spec.dependencies.find { |d| d.name == 'haveapi-client' }
          raise Error, "Wrong gem dependency: #{name}" unless dependency && dependency.requirement.to_s == "~> #{version}"
          next unless name == 'haveapi'

          required = %w[json-schema.html protocol.md create-client.md typed-input-validation.md protocol.png].map { |f| "doc/#{f}" }
          raise Error, 'Server gem is missing shared documentation' unless (required - package.contents).empty?
        end
        inspect_npm(directory)

        php = tar_files(File.join(directory, "haveapi-client-php-#{version}.tar"))
        raise Error, 'Wrong Composer identity' unless JSON.parse(php.fetch('composer.json').first).values_at('name', 'version') == ['haveapi/client', version]

        Release.capture('python', File.join(root, 'utils/release/python_artifacts.py'), directory, version)
      end

      def inspect_npm(directory)
        npm = tar_files(File.join(directory, "haveapi-client-#{version}.tgz"), gzip: true)
        metadata = JSON.parse(npm.fetch('package/package.json').first)
        repository = metadata.fetch('repository')
        unless metadata.values_at('name', 'version') == ['haveapi-client', version] && repository.fetch('url') == "https://github.com/#{REPOSITORY}"
          raise Error, 'Wrong npm identity or publishing repository'
        end
        unless metadata.values_at('main', 'types') == ['dist/haveapi-client.js', 'dist/types/haveapi.d.ts']
          raise Error, 'Wrong npm main or types entry'
        end

        required = %w[README.md doc-async-client.md doc-async-resources.md LICENSE.txt dist/types/haveapi.d.ts]
        required.each do |name|
          raise Error, "npm tarball is missing or has empty #{name}" unless npm.has_key?("package/#{name}") && !npm.fetch("package/#{name}").first.strip.empty?
        end
        npm.each do |name, (content, _mode)|
          next unless name.start_with?('package/dist/types/') && name.end_with?('.d.ts')

          raise Error, "Empty npm declaration: #{name}" if content.strip.empty?
        end

        bundle = File.binread(File.join(directory, 'haveapi-client.js'))
        raise Error, 'npm tarball does not contain the built bundle' unless npm.fetch('package/dist/haveapi-client.js').first == bundle
        raise Error, 'Wrong browser bundle version' unless bundle.include?("Client.Version = '#{version}'")
      end

      def smoke_npm(directory)
        inspect_npm(directory)
        archive = File.expand_path("haveapi-client-#{version}.tgz", directory)
        compiler = File.join(root, 'clients/js/node_modules/typescript/bin/tsc')
        Dir.mktmpdir('haveapi-npm-') do |tmp|
          env = { 'NODE_PATH' => nil }
          File.write(File.join(tmp, 'package.json'), JSON.generate({ name: 'haveapi-release-smoke', private: true }))
          Release.run(env, 'npm', 'install', '--ignore-scripts', '--no-audit', '--no-fund', archive, chdir: tmp)
          script = <<~JS
            const fs = require('fs');
            const assert = require('assert');
            assert.strictEqual(fs.realpathSync(require.resolve('haveapi-client')),
              fs.realpathSync('node_modules/haveapi-client/dist/haveapi-client.js'));
            const api = require('haveapi-client');
            assert.strictEqual(api.CallbackClient, api.Client);
            assert.strictEqual(api.Client.Version, process.argv[1]);
            new api.CallbackClient('http://localhost');
            new api.AsyncClient('http://localhost');
            console.log('Installed npm callback/async exports valid: ' + api.Client.Version);
          JS
          Release.run(env, 'node', '-e', script, version, chdir: tmp)
          FileUtils.cp(File.join(__dir__, 'npm-consumer.ts'), File.join(tmp, 'consumer.ts'))
          stdout, stderr, status = Open3.capture3(env, 'node', compiler, '--strict', '--noEmit', '--target', 'ES2020', '--module', 'commonjs',
                                                  '--moduleResolution', 'node', '--lib', 'ES2020,DOM', '--listFiles', 'consumer.ts', chdir: tmp)
          raise Error, "Installed npm declarations failed to compile:\n#{stdout}#{stderr}" unless status.success?

          files = stdout.lines.map(&:strip)
          types = File.realpath(File.join(tmp, 'node_modules/haveapi-client/dist/types'))
          compiler_lib = File.realpath(File.join(root, 'clients/js/node_modules/typescript/lib'))
          unless files.include?(File.join(types, 'haveapi.d.ts')) && files.all? do |path|
            actual = File.realpath(File.expand_path(path, tmp))
            actual == File.join(tmp, 'consumer.ts') || actual.start_with?("#{types}/", "#{compiler_lib}/")
          end
            raise Error, 'npm smoke resolved types outside the installed package or compiler library'
          end

          puts 'Installed npm declarations valid (package-name consumer)'
        end
      end
    end
  end
end
