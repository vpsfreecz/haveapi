require 'fileutils'
require 'pathname'
require 'tempfile'

module HaveAPI::TypeScriptClient
  class Generator
    ROOT = File.expand_path('../../..', __dir__)
    OWNER_FILE = '.haveapi-generated.json'.freeze
    OWNER = 'haveapi-typescript-client'.freeze
    CONFIG = { runtime_import: 'haveapi-client' }.freeze

    def self.source_files
      Dir.chdir(ROOT) do
        Dir['bin/**/*', 'lib/**/*.{rb,json}', 'template/**/*', 'Gemfile', '*.gemspec', 'Rakefile']
          .select { |path| File.file?(path) }.sort
      end
    end

    def self.source_digest
      digest = Digest::SHA256.new
      source_files.each do |path|
        digest.update(path).update("\0").update(File.binread(File.join(ROOT, path))).update("\0")
      end
      digest.update('haveapi/schema').update("\0").update(Snapshot.canonical(HaveAPI::Schema.source_identity)).update("\0")
      digest.hexdigest
    end

    def initialize(schema:, config: CONFIG)
      unless config == CONFIG
        raise Error, 'unsupported generator configuration'
      end

      @schema = Snapshot.validate(schema)
      @ir = IR.build(schema)
      @config = CONFIG
    end

    def generate(output:, check: false)
      output = File.expand_path(output)
      validate_destination(output)
      require_relative 'emitter'
      files = Emitter.new(@ir, @config).files
      validate_files(files)
      require_relative 'formatter'
      formatter = Formatter.new
      files = formatter.format(files)
      validate_files(files)
      manifest = {
        'owner' => OWNER, 'format' => 1, 'generator_version' => VERSION,
        'generator_source_sha256' => self.class.source_digest,
        'schema_sha256' => Snapshot.sha256(@schema), 'api_version' => @schema.fetch('api_version'),
        'protocol_version' => @schema.fetch('protocol_version'), 'profile' => @schema.fetch('profile'),
        'config' => @config.transform_keys(&:to_s), 'formatter' => formatter.provenance, 'coverage' => coverage,
        'files' => files.sort.to_h.transform_values { |content| Digest::SHA256.hexdigest(content) }
      }
      candidate = files.merge(OWNER_FILE => Snapshot.canonical(manifest))
      return true if equal_tree?(output, candidate)
      raise Error, 'generated tree is stale; regenerate without --check' if check

      install(output, candidate)
      true
    end

    private

    def coverage
      count_resources = lambda do |map|
        map.values.sum { |resource| 1 + count_resources.call(resource.fetch('resources')) }
      end
      count_actions = lambda do |map|
        map.values.sum { |resource| resource.fetch('actions').length + count_actions.call(resource.fetch('resources')) }
      end
      application = @schema.fetch('description').fetch('resources')
      auth = @schema.fetch('description').fetch('authentication').values.map { |config| config.fetch('resources', {}) }
      {
        'application_resource_count' => count_resources.call(application),
        'application_action_count' => @ir.fetch(:actions).length,
        'authentication_resource_count' => auth.sum { |map| count_resources.call(map) },
        'authentication_action_count' => auth.sum { |map| count_actions.call(map) },
        'authentication_exclusion' => 'Authentication resources are retained and validated; the existing runtime owns their API-root routes.'
      }
    end

    def safe_relative?(path)
      path.is_a?(String) && !path.empty? && !path.start_with?('/') && !path.include?('\\') &&
        !path.match?(/[\x00-\x1f\x7f]/) && path.split('/').none? { |part| ['', '.', '..'].include?(part) }
    end

    def validate_files(files)
      raise Error, 'emitter must return a nonempty file map including index.ts' unless files.is_a?(Hash) && files.has_key?('index.ts')

      files.each do |path, content|
        unless safe_relative?(path) && path != OWNER_FILE && content.is_a?(String) &&
               content.encoding == Encoding::UTF_8 && content.valid_encoding? && !content.include?("\r") && content.end_with?("\n")
          raise Error, "unsafe generated file or non-UTF-8/LF content: #{path.inspect}"
        end

        fail_conflict = files.keys.any? { |other| other != path && path.start_with?("#{other}/") }
        raise Error, "generated file/directory conflict: #{path}" if fail_conflict
      end
    end

    def validate_destination(output)
      unless File.basename(output) == 'generated' && File.basename(File.dirname(output)) == 'src'
        raise Error, 'output must be the exclusively generated src/generated directory'
      end

      cursor = output
      loop do
        raise Error, 'generated destination contains a symlink' if File.symlink?(cursor)
        break if cursor == File.dirname(cursor)

        cursor = File.dirname(cursor)
      end
      return unless File.exist?(output)
      raise Error, 'generated destination is not a directory' unless File.directory?(output)

      files = tree_files(output)
      return if files.empty? && Dir.empty?(output)

      marker = File.join(output, OWNER_FILE)
      raise Error, 'nonempty destination has no generator ownership manifest' unless File.file?(marker)

      owner = JSON.parse(File.read(marker))
      unless owner['owner'] == OWNER && owner['format'] == 1 && owner['files'].is_a?(Hash) &&
             owner['files'].all? { |path, hash| safe_relative?(path) && path != OWNER_FILE && hash.is_a?(String) && hash.match?(/\A[0-9a-f]{64}\z/) }
        raise Error, 'invalid generator ownership manifest'
      end

      unknown = files - owner.fetch('files').keys - [OWNER_FILE]
      raise Error, "destination contains files not owned by generator: #{unknown.join(', ')}" unless unknown.empty?
    rescue JSON::ParserError
      raise Error, 'invalid generator ownership JSON'
    end

    def tree_files(root)
      return [] unless File.directory?(root)

      Dir.glob('**/*', File::FNM_DOTMATCH, base: root).reject { |path| %w[. ..].include?(File.basename(path)) }.filter_map do |path|
        full = File.join(root, path)
        raise Error, "generated directory contains a symlink: #{path}" if File.symlink?(full)
        next if File.directory?(full)
        raise Error, "generated directory contains a nonregular file: #{path}" unless File.file?(full)

        path
      end.sort
    end

    def equal_tree?(output, candidate)
      tree_files(output) == candidate.keys.sort && candidate.all? do |path, content|
        File.binread(File.join(output, path)) == content.b
      end
    end

    def install(output, candidate)
      previous = tree_files(output)
      FileUtils.mkdir_p(output)
      # Each file replacement is atomic. The manifest is installed last so an
      # interrupted regeneration is recognized as drift by the next --check.
      candidate.reject { |path, _content| path == OWNER_FILE }.each { |path, content| write_file(output, path, content) }
      (previous - candidate.keys).each { |path| File.unlink(File.join(output, path)) }
      write_file(output, OWNER_FILE, candidate.fetch(OWNER_FILE))
      Dir.glob('**/*', base: output).sort.reverse_each do |path|
        full = File.join(output, path)
        Dir.rmdir(full) if File.directory?(full) && Dir.empty?(full)
      end
    end

    def write_file(output, path, content)
      target = File.join(output, path)
      FileUtils.mkdir_p(File.dirname(target))
      Tempfile.create(['.haveapi-', '.tmp'], File.dirname(target)) do |temp|
        temp.binmode
        temp.write(content)
        temp.close
        File.rename(temp.path, target)
      end
    end
  end
end
