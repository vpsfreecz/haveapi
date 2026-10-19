require 'erb'
require 'fileutils'
require 'tmpdir'
require 'open3'
require 'fiddle/import'
require 'tomlrb'

module HaveAPI::RustClient
  class Generator
    ROOT = File.expand_path('../../..', __dir__)
    CONFIG_KEYS = %w[crate_name crate_version license edition rust_version rustfmt_version].freeze
    OWNER_FILE = '.haveapi-generated.json'.freeze
    attr_reader :schema, :config, :ir

    def initialize(schema:, config:)
      @schema = Snapshot.validate(schema)
      @config = config
      validate_config
      @ir = IR.new(schema)
    end

    def generate(output:, check: false)
      output = File.expand_path(output)
      validate_destination(output)
      validate_manifest(output)
      formatter = ENV.fetch('RUSTFMT', 'rustfmt')
      stdout, _stderr, status = Open3.capture3(formatter, '--version')
      unless status.success? && stdout.strip == config.fetch('rustfmt_version')
        raise Error, 'rustfmt version differs from generator configuration'
      end

      Dir.mktmpdir('haveapi-rust-') do |temp|
        render_tree(temp)
        generated = Dir.glob(File.join(temp, '**/*.rs')).reject { |path| path.start_with?(File.join(temp, 'runtime/')) }
        _stdout, stderr, status = Open3.capture3(
          formatter, '--edition', config.fetch('edition'), '--config', 'skip_children=true', *generated
        )
        raise Error, "rustfmt failed: #{stderr.lines.first&.strip}" unless status.success?

        files = tree_files(temp)
        manifest = {
          'owner' => 'haveapi-rust-client', 'format' => 1,
          'generator_version' => VERSION, 'generator_source_sha256' => generator_digest,
          'schema_sha256' => Snapshot.sha256(schema), 'runtime_sha256' => runtime_digest,
          'api_version' => schema.fetch('api_version'), 'protocol_version' => schema.fetch('protocol_version'),
          'profile' => schema.fetch('profile'), 'config' => config,
          'ruby_dependency_lock_sha256' => Digest::SHA256.file(File.join(ROOT, 'Gemfile.lock')).hexdigest,
          'files' => files.to_h { |path| [path, Digest::SHA256.file(File.join(temp, path)).hexdigest] }
        }
        File.write(File.join(temp, OWNER_FILE), Snapshot.canonical(manifest))
        return true if equal_trees?(temp, output)
        raise Error, 'generated tree is stale; regenerate without --check' if check

        install_tree(temp, output)
      end
      true
    rescue Errno::ENOENT
      raise Error, 'required generation file/tool is missing'
    end

    def runtime_digest
      digest_files(runtime_files, File.join(ROOT, 'runtime/src/runtime'))
    end

    def manifest_requirements
      render('Cargo.toml', {})
    end

    private

    def validate_config
      raise Error, 'generator config keys do not match supported contract' unless config.keys.sort == CONFIG_KEYS.sort
      unless config['crate_name'].is_a?(String) && config['crate_name'].match?(/\A[a-z][a-z0-9_-]*\z/) &&
             config['crate_version'].is_a?(String) && config['crate_version'].match?(/\A\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?\z/)
        raise Error, 'invalid crate name/version'
      end
      unless config['license'] == 'MIT' && config['edition'] == '2024' && config['rust_version'] == '1.95' &&
             config['rustfmt_version'].is_a?(String) && !config['rustfmt_version'].empty?
        raise Error, 'unsupported license, Rust edition/MSRV or formatter configuration'
      end
    end

    def validate_manifest(output)
      return unless File.basename(output) == 'generated' && File.basename(File.dirname(output)) == 'src'

      path = File.join(File.dirname(output, 2), 'Cargo.toml')
      return unless File.exist?(path)
      raise Error, 'crate manifest must not be a symlink' if File.symlink?(path)

      manifest = Tomlrb.load_file(path)
      package = manifest.fetch('package')
      %w[name version license edition rust-version].zip(%w[crate_name crate_version license edition rust_version]).each do |cargo, key|
        raise Error, "Cargo.toml #{cargo} differs from generator config" unless package[cargo] == config[key]
      end
      deps = manifest.fetch('dependencies')
      { 'serde' => '1', 'serde_json' => '1', 'url' => '2.5', 'reqwest' => '0.13.5' }.each do |name, version|
        dependency = deps.fetch(name)
        actual = dependency.is_a?(Hash) ? dependency['version'] : dependency
        unless actual == version && (!dependency.is_a?(Hash) || !dependency.keys.intersect?(%w[path git]))
          raise Error, "Cargo.toml dependency #{name} differs from runtime requirements"
        end
      end
      unless deps['serde'].is_a?(Hash) && deps['serde'].fetch('features', []).include?('derive')
        raise Error, 'Cargo.toml serde derive feature is required'
      end

      reqwest = deps.fetch('reqwest')
      unless reqwest.is_a?(Hash) && reqwest['default-features'] == false &&
             reqwest.fetch('features', []).sort == %w[json rustls] &&
             manifest.dig('features', 'default') == [] &&
             manifest.dig('features', 'blocking')&.include?('reqwest/blocking')
        raise Error, 'Cargo.toml reqwest TLS/JSON/blocking requirements do not match runtime'
      end
    rescue KeyError, Tomlrb::ParseError
      raise Error, 'crate manifest is incomplete or invalid TOML'
    end

    def render_tree(temp)
      File.write(File.join(temp, 'mod.rs'), render('mod.rs', {}))
      FileUtils.mkdir_p(File.join(temp, 'resources'))
      File.write(File.join(temp, 'resources/mod.rs'), render('resources.rs', {}))
      ir.resources.each do |resource|
        dir = File.join(temp, 'resources', resource[:module])
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, 'mod.rs'), render('resource.rs', resource:))
        resource[:actions].each do |action|
          File.write(File.join(dir, "#{action[:method]}.rs"), render('action.rs', action:))
        end
      end
      runtime_files.each do |relative|
        target = File.join(temp, 'runtime', relative)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(File.join(ROOT, 'runtime/src/runtime', relative), target)
      end
    end

    def render(template, locals)
      ERB.new(File.read(File.join(ROOT, 'template', "#{template}.erb")), trim_mode: '-').result_with_hash(
        { generator: self, schema:, config:, ir: }.merge(locals)
      )
    end

    def runtime_files
      root = File.join(ROOT, 'runtime/src/runtime')
      raise Error, 'maintained runtime source is missing' unless File.file?(File.join(root, 'mod.rs'))

      ensure_no_symlinks(root)
      tree_files(root)
    end

    def generator_digest
      paths = Dir.chdir(ROOT) { Dir['lib/**/*.rb', 'template/**/*'].select { |path| File.file?(path) }.sort }
      digest_files(paths, ROOT)
    end

    def digest_files(paths, root)
      digest = Digest::SHA256.new
      paths.sort.each { |path| digest.update(path).update("\0").update(File.binread(File.join(root, path))).update("\0") }
      digest.hexdigest
    end

    def validate_destination(output)
      raise Error, 'refusing filesystem root output' if output == '/'

      cursor = output
      loop do
        raise Error, 'generated destination contains a symlink' if File.symlink?(cursor)
        break if cursor == File.dirname(cursor)

        cursor = File.dirname(cursor)
      end
      return unless File.exist?(output)
      raise Error, 'generated destination is not a directory' unless File.directory?(output)

      ensure_no_symlinks(output)
      entries = tree_files(output)
      return if entries.empty?

      marker = File.join(output, OWNER_FILE)
      raise Error, 'nonempty destination has no generator ownership manifest' unless File.file?(marker)

      owner = JSON.parse(File.read(marker))
      unless owner['owner'] == 'haveapi-rust-client' && owner['format'] == 1 && owner['files'].is_a?(Hash)
        raise Error, 'invalid generator ownership manifest'
      end

      owner.fetch('files').each_key do |path|
        unless path.is_a?(String) && !path.start_with?('/') && Snapshot.safe_segments?(path)
          raise Error, 'unsafe owned path in manifest'
        end
      end
      unknown = entries - owner.fetch('files').keys - [OWNER_FILE]
      raise Error, 'destination contains files not owned by generator' unless unknown.empty?
    rescue JSON::ParserError
      raise Error, 'invalid generator ownership JSON'
    end

    def ensure_no_symlinks(root)
      return unless Dir.glob(File.join(root, '**/*'), File::FNM_DOTMATCH).any? { |path| File.symlink?(path) }

      raise Error, 'symlink in generator-owned source/destination'
    end

    def tree_files(root)
      return [] unless File.directory?(root)

      Dir.chdir(root) { Dir.glob('**/*', File::FNM_DOTMATCH).select { |path| File.file?(path) }.sort }
    end

    def equal_trees?(left, right)
      files = tree_files(left)
      files == tree_files(right) && files.all? do |path|
        File.binread(File.join(left, path)) == File.binread(File.join(right, path))
      end
    end

    def install_tree(temp, output)
      FileUtils.mkdir_p(File.dirname(output))
      Dir.mktmpdir('.haveapi-rust-', File.dirname(output)) do |staging|
        replacement = File.join(staging, 'generated')
        FileUtils.cp_r(temp, replacement)
        if File.exist?(output)
          # Directory exchange is atomic even for a nonempty destination. Refuse
          # unsupported hosts instead of exposing a half-replaced generated tree.
          AtomicRename.exchange(replacement, output)
        else
          File.rename(replacement, output)
        end
      end
    end

    module AtomicRename
      extend Fiddle::Importer

      dlload Fiddle.dlopen(nil)

      def self.exchange(left, right)
        function = Fiddle::Function.new(handler['renameat2'], [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP,
                                                               Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP,
                                                               Fiddle::TYPE_INT], Fiddle::TYPE_INT)
        return if function.call(-100, left, -100, right, 2) == 0

        raise Error, 'atomic generated-directory exchange failed'
      rescue Fiddle::DLError
        raise Error, 'atomic replacement requires renameat2 support on this host'
      end
    end

    public

    def literal(value)
      Naming.literal(value)
    end

    def option(value)
      value.nil? ? 'None' : "Some(#{literal(value)})"
    end

    def layout(value)
      value.split('_').map(&:capitalize).join
    end

    def rust_type(parameter, output: false)
      case parameter[:desc].fetch('type')
      when 'String', 'Text', 'Datetime' then 'String'
      when 'Integer', 'Resource' then output && parameter[:desc]['type'] == 'Resource' ? 'runtime::Association' : 'i64'
      when 'Float' then 'f64'
      when 'Boolean' then 'bool'
      when 'Custom' then 'serde_json::Value'
      end
    end

    def input_type(action)
      return '()' unless action[:input]

      action[:input][:layout].end_with?('_list') ? 'Vec<Input>' : 'Input'
    end

    def output_type(action)
      return '()' unless action[:output]

      action[:output][:layout].end_with?('_list') ? 'Vec<Output>' : 'Output'
    end

    def meta_parameters(action)
      values = [action[:global_output]]
      values << action[:object_output] if action[:output] && !action[:output][:layout].end_with?('_list')
      fields = values.compact.flat_map { |io| io[:parameters] }
      fields.group_by { |field| field[:name] }.map do |name, matches|
        raise Error, "inconsistent metadata field #{name}" if matches.map { |field| field[:desc] }.uniq.length > 1

        matches.first
      end.sort_by { |field| field[:name] }
    end

    def parameter_specs(io)
      return '&[]' unless io

      parameters = io[:parameters].map do |parameter|
        desc = parameter[:desc]
        "runtime::ParameterSpec { name: #{literal(parameter[:name])}, kind: runtime::ParameterKind::#{desc.fetch('type')}, " \
          "required: #{desc['required'] == true}, nullable: #{desc['nullable'] == true}, protected: #{desc['protected'] == true} }"
      end.join(',')
      "&[#{parameters}]"
    end
  end
end
