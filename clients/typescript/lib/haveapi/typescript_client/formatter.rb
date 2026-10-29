require 'digest'
require 'fileutils'
require 'open3'
require 'tmpdir'

module HaveAPI::TypeScriptClient
  # Format only the validated emission tree, before the generator hashes it.
  class Formatter
    VERSION = '3.9.10'.freeze
    CONFIG = File.expand_path('prettier.json', __dir__).freeze

    def initialize
      @executable = ENV.fetch('PRETTIER', 'prettier')
      @executable = File.expand_path(@executable) if @executable.include?(File::SEPARATOR)
    end

    def version
      actual = capture('--version').strip
      raise Error, "Prettier #{VERSION} is required; found #{actual.inspect}" unless actual == VERSION

      actual
    end

    def provenance
      { 'name' => 'prettier', 'version' => VERSION, 'config_sha256' => Digest::SHA256.file(CONFIG).hexdigest }
    end

    def format(files)
      version
      Dir.mktmpdir('haveapi-typescript-format-') do |directory|
        files.each do |path, content|
          target = File.join(directory, path)
          FileUtils.mkdir_p(File.dirname(target))
          File.write(target, content)
        end
        capture('--config', CONFIG, '--no-editorconfig', '--ignore-path', File::NULL,
                '--parser', 'typescript', '--write', '**/*.ts', chdir: directory)
        files.to_h do |path, _content|
          [path, File.read(File.join(directory, path), encoding: 'UTF-8')]
        end
      end
    rescue SystemCallError => e
      raise Error, "Prettier formatting failed: #{e.message}"
    end

    private

    def capture(*, **)
      stdout, stderr, status = Open3.capture3(@executable, *, **)
      raise Error, "Prettier failed: #{stderr.strip}" unless status.success?

      stdout
    rescue SystemCallError => e
      raise Error, "Unable to run Prettier #{@executable.inspect}: #{e.message}"
    end
  end
end
