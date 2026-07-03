require 'yaml'

module HaveAPI
  module Tasks
    class I18nHealth
      KEY_LITERAL_PATTERN = /['"](haveapi\.[a-z0-9_.]+)['"]/

      RAW_MESSAGE_PATTERNS = [
        /report_error\([^#\n]*,\s*['"]/,
        /error!\(\s*['"]/,
        /HaveAPI::ValidationError(?:\.new)?\(\s*['"]/,
        /raise\s+HaveAPI::ValidationError,\s*['"]/,
        /ret\[:message\]\s*=\s*['"]/,
        /\|\|\s*['"][^'"]+(?:failed|error|denied|not found|invalid|requires|unsupported|missing)/,
        /@message\s*=\s*take\(\s*:message\s*,\s*['"]/
      ].freeze

      def initialize(root:)
        @root = root
      end

      def check!
        errors = []
        errors.concat(missing_key_errors)
        errors.concat(unused_key_errors)
        errors.concat(raw_message_errors)

        return true if errors.empty?

        raise "i18n health check failed:\n#{errors.join("\n")}"
      end

      def normalize!
        locale_data.each do |locale, data|
          file = File.join(locale_dir, "#{locale}.yml")
          File.write(file, YAML.dump(locale.to_s => deep_sort(data)))
        end
      end

      private

      def missing_key_errors
        reference_locale = :en
        reference_keys = locale_keys.fetch(reference_locale)

        locale_keys.flat_map do |locale, keys|
          next [] if locale == reference_locale

          (reference_keys - keys).sort.map do |key|
            "#{locale}: missing #{key}"
          end
        end
      end

      def unused_key_errors
        keys = locale_keys.fetch(:en)
        used = used_keys

        (keys - used).sort.map { |key| "unused translation key #{key}" }
      end

      def raw_message_errors
        source_files.flat_map do |file|
          rel = relative_path(file)

          File.readlines(file, chomp: true).each_with_index.filter_map do |line, index|
            stripped = line.strip
            next if stripped.empty? || stripped.start_with?('#')

            if RAW_MESSAGE_PATTERNS.any? { |pattern| pattern.match?(line) }
              "#{rel}:#{index + 1}: raw user-facing framework message"
            end
          end
        end
      end

      def used_keys
        @used_keys ||= source_files.each_with_object(Set.new) do |file, ret|
          File.read(file).scan(KEY_LITERAL_PATTERN) do |match|
            ret << match.first
          end
        end
      end

      def locale_keys
        @locale_keys ||= locale_data.transform_values do |data|
          flatten_keys(data)
        end
      end

      def locale_data
        @locale_data ||= Dir[File.join(locale_dir, '*.yml')].to_h do |file|
          locale = File.basename(file, '.yml').to_sym
          data = YAML.safe_load_file(file, aliases: true) || {}

          [locale, data.fetch(locale.to_s)]
        end
      end

      def flatten_keys(hash, prefix = nil)
        hash.each_with_object(Set.new) do |(key, value), ret|
          name = [prefix, key].compact.join('.')

          if value.is_a?(Hash)
            ret.merge(flatten_keys(value, name))
          else
            ret << name
          end
        end
      end

      def deep_sort(value)
        case value
        when Hash
          value.keys.sort.to_h do |key|
            [key, deep_sort(value[key])]
          end
        else
          value
        end
      end

      def source_files
        @source_files ||= Dir[File.join(@root, 'lib/haveapi/**/*.rb')].reject do |file|
          rel = relative_path(file)
          rel.start_with?('lib/haveapi/public/') ||
            rel.start_with?('lib/haveapi/views/') ||
            rel.start_with?('lib/haveapi/client_examples/') ||
            rel.start_with?('lib/haveapi/spec/') ||
            rel.start_with?('lib/haveapi/tasks/i18n.rb')
        end
      end

      def relative_path(file)
        file.delete_prefix("#{@root}/")
      end

      def locale_dir
        File.join(@root, 'lib/haveapi/locales')
      end
    end
  end
end

namespace :i18n do
  desc 'Check HaveAPI translation coverage and raw framework messages'
  task :health do
    HaveAPI::Tasks::I18nHealth.new(root: File.expand_path('../../..', __dir__)).check!
  end

  desc 'Normalize HaveAPI locale files'
  task :normalize do
    HaveAPI::Tasks::I18nHealth.new(root: File.expand_path('../../..', __dir__)).normalize!
  end
end
