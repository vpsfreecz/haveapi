require 'net/http'
require 'shellwords'
require_relative 'artifacts'

module HaveAPI
  module Release
    class Publisher
      def initialize(artifacts, directory)
        @artifacts = artifacts
        @directory = File.expand_path(directory)
        @manifest = artifacts.verify(@directory)
      end

      def registry_json(url)
        uri = URI(url)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) do |http|
          http.get(uri.request_uri)
        end
        return nil if response.code == '404'

        raise Error, "Registry query failed (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end

      def gem_present?(name)
        metadata = registry_json("https://rubygems.org/api/v2/rubygems/#{name}/versions/#{@artifacts.version}.json")
        return false unless metadata

        expected = @manifest.fetch('files').fetch("#{name}-#{@artifacts.version}.gem")
        raise Error, "Existing RubyGems version differs: #{name}" unless metadata.fetch('sha') == expected

        true
      end

      def npm_present?
        metadata = registry_json("https://registry.npmjs.org/haveapi-client/#{@artifacts.version}")
        return false unless metadata

        expected = "sha512-#{Digest::SHA512.file(File.join(@directory, "haveapi-client-#{@artifacts.version}.tgz")).base64digest}"
        unless metadata.values_at('name', 'version') == ['haveapi-client', @artifacts.version] && metadata.fetch('dist').fetch('integrity').split.include?(expected)
          raise Error, 'Existing npm version differs'
        end

        true
      end

      def confirm
        12.times do
          return if yield

          sleep 5
        end
        raise Error, 'Publication was not confirmed by the registry; rerun with the retained artifacts'
      end

      def publish_registries
        existing_gems = GEMS.keys.to_h { |name| [name, gem_present?(name)] }
        existing_npm = npm_present?
        npm_version = Gem::Version.new(Release.capture('npm', '--version').strip)
        raise Error, 'Trusted publishing requires npm >= 11.5.1' if !existing_npm && npm_version < Gem::Version.new('11.5.1')

        GEMS.each_key do |name|
          unless existing_gems.fetch(name)
            Release.run('gem', 'push', File.join(@directory, "#{name}-#{@artifacts.version}.gem"), '--host', 'https://rubygems.org')
            confirm { gem_present?(name) }
          end
          puts "Confirmed RubyGems: #{name} #{@artifacts.version}"
        end
        unless existing_npm
          Release.run('npm', 'publish', File.join(@directory, "haveapi-client-#{@artifacts.version}.tgz"), '--ignore-scripts', '--access', 'public', '--registry', 'https://registry.npmjs.org')
          confirm { npm_present? }
        end
        puts "Confirmed npm: haveapi-client #{@artifacts.version}"
      end

      def protected_php_path?(path)
        path == 'AGENTS.md' || path == '.github' || path.start_with?('.github/')
      end

      def php_snapshot
        @artifacts.tar_files(File.join(@directory, "haveapi-client-php-#{@artifacts.version}.tar"))
      end

      def mirror_snapshot(mirror, ref)
        Dir.mktmpdir('haveapi-php-tree-') do |tmp|
          archive = File.join(tmp, 'tree.tar')
          # Archive the tree so Git does not add a commit-level PAX metadata header.
          Release.run('git', 'archive', '--format=tar', "--output=#{archive}", "#{ref}^{tree}", chdir: mirror)
          @artifacts.tar_files(archive).reject { |path, _| protected_php_path?(path) }
        end
      end

      # mirror is an isolated clone owned by this publication, never a workspace checkout.
      def preflight_php(mirror)
        snapshot = php_snapshot
        raise Error, 'PHP source conflicts with mirror-owned metadata' if snapshot.keys.any? { |path| protected_php_path?(path) }

        tag = @artifacts.tag
        tags = Release.capture('git', 'tag', '--list', tag, chdir: mirror).strip
        unless tags.empty?
          message = Release.capture('git', 'log', '-1', '--format=%B', tag, chdir: mirror)
          unless mirror_snapshot(mirror, tag) == snapshot && message.lines.map(&:strip).include?("HaveAPI-Source: #{@artifacts.source}")
            raise Error, 'Existing PHP tag has different content or source provenance'
          end

          return true
        end

        current_tags = Release.capture('git', 'tag', '--points-at', 'HEAD', chdir: mirror).lines.map(&:strip)
        unless current_tags.any? { |t| t.match?(/\Av\d+\.\d+\.\d+\z/) }
          raise Error, 'PHP master has untagged changes; inspect the mirror before publication'
        end

        current = mirror_snapshot(mirror, 'HEAD')
        current_version = JSON.parse(current.fetch('composer.json').first).fetch('version')
        unless Gem::Version.new(current_version) < Gem::Version.new(@artifacts.version)
          raise Error, 'Refusing to move PHP master to an older or conflicting version'
        end

        false
      end

      def sync_php(mirror, transport: {})
        if preflight_php(mirror)
          puts "Confirmed PHP tag: #{@artifacts.tag}"
          return
        end

        snapshot = php_snapshot
        current = mirror_snapshot(mirror, 'HEAD')
        tag = @artifacts.tag
        owned = (current.keys + snapshot.keys).uniq
        current.each_key { |path| FileUtils.rm_f(File.join(mirror, path)) }
        snapshot.each do |path, (content, mode)|
          destination = File.join(mirror, path)
          FileUtils.mkdir_p(File.dirname(destination))
          File.write(destination, content, mode: 'wb', perm: mode)
        end
        Release.run('git', 'add', '--all', '--', *owned, chdir: mirror)
        Dir.mktmpdir('haveapi-php-message-') do |tmp|
          message = File.join(tmp, 'message')
          File.write(message, "Release #{@artifacts.version}\n\nHaveAPI-Source: #{@artifacts.source}\n")
          author = ['git', '-c', 'user.name=github-actions[bot]', '-c', 'user.email=41898282+github-actions[bot]@users.noreply.github.com']
          Release.run(*author, 'commit', '-F', message, chdir: mirror)
          Release.run(*author, 'tag', '-a', tag, '-F', message, chdir: mirror)
        end
        Release.run(transport, 'git', 'push', '--atomic', 'origin', 'HEAD:refs/heads/master', "refs/tags/#{tag}", chdir: mirror)
        raise Error, 'PHP mirror content differs after synchronization' unless mirror_snapshot(mirror, tag) == snapshot

        puts "Confirmed PHP tag: #{tag}; Packagist indexing follows its configured webhook"
      end

      def php_key
        key = ENV.fetch('HAVEAPI_PHP_DEPLOY_KEY')
        raise Error, 'PHP deploy key is empty' if key.strip.empty?

        "#{key.strip}\n"
      end

      def with_php_mirror
        Dir.mktmpdir('haveapi-php-publish-') do |tmp|
          key_path = File.join(tmp, 'key')
          File.write(key_path, php_key, perm: 0o600)
          ssh = ['ssh', '-i', key_path, '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=yes', '-o', "UserKnownHostsFile=#{File.join(@artifacts.root, 'utils/release/github_known_hosts')}"]
          env = { 'GIT_SSH_COMMAND' => Shellwords.join(ssh) }
          mirror = File.join(tmp, 'mirror')
          Release.run(env, 'git', 'clone', '--quiet', '--branch', 'master', PHP_REPOSITORY, mirror)
          yield mirror, env
        end
      end

      def publish
        with_php_mirror do |mirror, transport|
          preflight_php(mirror)
          publish_registries
          sync_php(mirror, transport:)
          finish_github
        end
      end

      def github_api(*)
        stdout, stderr, status = Open3.capture3('gh', 'api', *)
        raise Error, "GitHub release query failed: #{stderr.strip}" unless status.success?

        JSON.parse(stdout)
      end

      def github_release
        # Draft pending tags require GraphQL; REST may expose an untagged-* name.
        owner, repository = REPOSITORY.split('/')
        query = <<~GRAPHQL
          query($tag: String!) {
            repository(owner: "#{owner}", name: "#{repository}") {
              release(tagName: $tag) { databaseId }
            }
          }
        GRAPHQL
        result = github_api('graphql', '-f', "query=#{query}", '-f', "tag=#{@artifacts.tag}")
        release = result.fetch('data').fetch('repository').fetch('release')
        return nil if release.nil?

        github_api("repos/#{REPOSITORY}/releases/#{release.fetch('databaseId')}")
      end

      def prepare_github
        release = github_release
        unless release
          Release.run('gh', 'release', 'create', @artifacts.tag, '--repo', REPOSITORY, '--verify-tag', '--draft', '--title', "HaveAPI #{@artifacts.version}", '--notes-file', File.join(@directory, 'release-notes.md'))
          release = github_release
          raise Error, 'Created GitHub draft was not found by its pending tag' unless release
        end
        asset_names = release.fetch('assets').map { |asset| asset.fetch('name') }
        (@artifacts.names + ['release-manifest.json']).each do |name|
          path = File.join(@directory, name)
          if asset_names.include?(name)
            Dir.mktmpdir('haveapi-asset-') do |tmp|
              Release.run('gh', 'release', 'download', @artifacts.tag, '--repo', REPOSITORY, '--pattern', name, '--dir', tmp)
              unless Digest::SHA256.file(File.join(tmp, name)).hexdigest == Digest::SHA256.file(path).hexdigest
                raise Error, "Existing GitHub asset differs: #{name}"
              end
            end
          else
            raise Error, 'Existing public GitHub Release has missing artifacts' unless release.fetch('draft')

            Release.run('gh', 'release', 'upload', @artifacts.tag, path, '--repo', REPOSITORY)
          end
        end
      end

      def finish_github
        raise Error, 'Registry publication is incomplete' unless GEMS.keys.all? { |name| gem_present?(name) } && npm_present?

        Release.run('gh', 'release', 'edit', @artifacts.tag, '--repo', REPOSITORY, '--draft=false') if github_release.fetch('draft')
        puts "Release complete: https://github.com/#{REPOSITORY}/releases/tag/#{@artifacts.tag}"
      end
    end
  end
end
