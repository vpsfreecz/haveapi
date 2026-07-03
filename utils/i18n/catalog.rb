require 'fileutils'
require 'json'
require 'yaml'

module HaveAPI
  module I18n
    class Catalog
      DEFAULT_LOCALE = 'en'.freeze

      SOURCE_PATH = 'i18n/haveapi.yml'.freeze

      LOCALIZED_YAML_ARTIFACTS = [
        {
          path: 'servers/ruby/lib/haveapi/locales/%<locale>s.yml',
          scope: 'haveapi',
          format: :yaml
        },
        {
          path: 'clients/ruby/lib/haveapi/client/locales/%<locale>s.yml',
          scope: 'haveapi_client',
          format: :yaml
        }
      ].freeze

      GENERATED_FILES = [
        {
          path: 'clients/php/src/Client/I18nMessages.php',
          scope: 'haveapi_client',
          format: :php
        },
        {
          path: 'clients/js/src/haveapi/i18n_messages.js',
          scope: 'haveapi_client',
          format: :js
        },
        {
          path: 'clients/go/lib/haveapi/go_client/i18n_messages.yml',
          scope: 'haveapi_client',
          format: :yaml_all
        }
      ].freeze

      SCAN_GLOBS = [
        'servers/ruby/lib/haveapi/**/*.rb',
        'clients/ruby/lib/**/*.rb',
        'clients/php/src/**/*.php',
        'clients/js/src/**/*.js',
        'clients/go/template/**/*.erb'
      ].freeze

      SCAN_EXCLUDES = [
        'servers/ruby/lib/haveapi/locales/',
        'servers/ruby/lib/haveapi/spec/',
        'servers/ruby/lib/haveapi/tasks/i18n.rb',
        'clients/ruby/lib/haveapi/client/i18n.rb',
        'clients/ruby/lib/haveapi/client/locales/',
        'clients/php/src/Client/I18n.php',
        'clients/php/src/Client/I18nMessages.php',
        'clients/js/src/haveapi/i18n.js',
        'clients/js/src/haveapi/i18n_messages.js'
      ].freeze

      KEY_PATTERN = /[a-z0-9_]+(?:\.[a-z0-9_]+)+/
      FULL_KEY_LITERAL_PATTERN = /['"]((?:haveapi|haveapi_client)\.#{KEY_PATTERN})['"]/
      CLIENT_KEY_LITERAL_PATTERNS = [
        /client_message\(\s*['"](#{KEY_PATTERN})['"]/,
        /translate\(\s*['"](#{KEY_PATTERN})['"]/,
        /\.translate\(\s*['"](#{KEY_PATTERN})['"]/,
        /t\([^,\n]+,\s*["'](#{KEY_PATTERN})["']/
      ].freeze

      SERVER_RAW_MESSAGE_PATTERNS = [
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

      def update!
        generated_files.each do |entry|
          write_file(entry[:path], render(entry))
        end
      end

      def check!
        errors = []
        errors.concat(locale_key_errors)
        errors.concat(interpolation_errors)
        errors.concat(used_key_errors)
        errors.concat(generated_file_errors)
        errors.concat(raw_message_errors)

        return true if errors.empty?

        raise "i18n health check failed:\n#{errors.join("\n")}"
      end

      private

      attr_reader :root

      def locale_key_errors
        reference_keys = flatten_keys(catalog.fetch(DEFAULT_LOCALE))

        locales.flat_map do |locale|
          keys = flatten_keys(catalog.fetch(locale))
          missing = reference_keys - keys
          extra = keys - reference_keys

          missing.sort.map { |key| "#{locale}: missing #{key}" } +
            extra.sort.map { |key| "#{locale}: extra #{key}" }
        end
      end

      def interpolation_errors
        reference = flatten_values(catalog.fetch(DEFAULT_LOCALE))

        locales.flat_map do |locale|
          next [] if locale == DEFAULT_LOCALE

          values = flatten_values(catalog.fetch(locale))

          reference.filter_map do |key, message|
            placeholders = interpolation_names(message)
            other_placeholders = interpolation_names(values[key])

            if placeholders != other_placeholders
              "#{locale}: interpolation mismatch for #{key}"
            end
          end
        end
      end

      def generated_file_errors
        generated_files.filter_map do |entry|
          path = absolute_path(entry[:path])

          if File.exist?(path)
            next if File.read(path) == render(entry)

            "#{entry[:path]}: generated file is not up to date; run rake i18n:update"
          else
            "#{entry[:path]}: generated file is missing"
          end
        end
      end

      def used_key_errors
        keys = flatten_keys(catalog.fetch(DEFAULT_LOCALE))

        (used_keys - keys).sort.map { |key| "missing translation key #{key}" }
      end

      def raw_message_errors
        client_raw_message_errors + server_raw_message_errors
      end

      def client_raw_message_errors
        messages = catalog.fetch(DEFAULT_LOCALE).fetch('haveapi_client')
        exact_messages = flatten_values(messages).values.reject do |value|
          value.include?('%{')
        end

        client_source_files.flat_map do |file|
          rel = relative_path(file)
          text = File.read(file)

          exact_messages.filter_map do |message|
            next unless message.length >= 8 && text.include?(message)

            "#{rel}: raw translatable client message #{message.inspect}"
          end
        end
      end

      def server_raw_message_errors
        server_source_files.flat_map do |file|
          rel = relative_path(file)

          File.readlines(file, chomp: true).each_with_index.filter_map do |line, index|
            stripped = line.strip
            next if stripped.empty? || stripped.start_with?('#')

            if SERVER_RAW_MESSAGE_PATTERNS.any? { |pattern| pattern.match?(line) }
              "#{rel}:#{index + 1}: raw user-facing framework message"
            end
          end
        end
      end

      def render(entry)
        case entry[:format]
        when :yaml
          locale = entry.fetch(:locale)
          generated_comment(:yaml) +
            YAML.dump(locale => { entry.fetch(:scope) => scoped_catalog(locale, entry[:scope]) })
        when :yaml_all
          generated_comment(:yaml) +
            YAML.dump(locales.to_h { |locale| [locale, scoped_catalog(locale, entry[:scope])] })
        when :php
          render_php(entry.fetch(:scope))
        when :js
          render_js(entry.fetch(:scope))
        else
          raise "unsupported i18n artifact format #{entry[:format].inspect}"
        end
      end

      def render_php(scope)
        data = locales.to_h { |locale| [locale, scoped_catalog(locale, scope)] }

        <<~PHP
          <?php

          #{generated_comment(:php)}
          namespace HaveAPI\\Client;

          final class I18nMessages
          {
              public const MESSAGES = #{php_value(data, 1)};
          }
        PHP
      end

      def render_js(scope)
        data = locales.to_h { |locale| [locale, scoped_catalog(locale, scope)] }
        json = JSON.pretty_generate(data).gsub(/^/, "\t").sub(/\A\t/, '')

        <<~JS
          #{generated_comment(:js)}
          var I18nMessages = #{json};
        JS
      end

      def generated_comment(format)
        prefix = case format
                 when :yaml
                   '#'
                 when :php, :js
                   '//'
                 else
                   raise "unsupported generated comment format #{format.inspect}"
                 end

        [
          "#{prefix} This file is generated from #{SOURCE_PATH}.",
          "#{prefix} Do not edit it manually; manual changes will be overwritten.",
          "#{prefix} Update #{SOURCE_PATH} and run bundle exec rake i18n:update.",
          ''
        ].join("\n")
      end

      def php_value(value, depth)
        indent = '    ' * depth
        inner_indent = '    ' * (depth + 1)

        case value
        when Hash
          return '[]' if value.empty?

          parts = value.map do |key, child|
            "#{inner_indent}#{php_value(key.to_s, 0)} => #{php_value(child, depth + 1)},"
          end

          "[\n#{parts.join("\n")}\n#{indent}]"
        when String
          "'#{value.gsub('\\', '\\\\\\').gsub("'", "\\\\'")}'"
        else
          raise "unsupported PHP i18n value #{value.inspect}"
        end
      end

      def scoped_catalog(locale, scope)
        deep_sort(catalog.fetch(locale).fetch(scope))
      end

      def generated_files
        @generated_files ||= begin
          localized = LOCALIZED_YAML_ARTIFACTS.flat_map do |entry|
            locales.map do |locale|
              entry.merge(
                path: format(entry.fetch(:path), locale:),
                locale:
              )
            end
          end

          localized + GENERATED_FILES
        end
      end

      def locales
        @locales ||= begin
          other_locales = catalog.keys.reject { |locale| locale == DEFAULT_LOCALE }.sort
          [DEFAULT_LOCALE] + other_locales
        end
      end

      def catalog
        @catalog ||= begin
          data = YAML.safe_load_file(absolute_path(SOURCE_PATH), aliases: true) || {}
          data.fetch(DEFAULT_LOCALE)
          data
        end
      end

      def flatten_keys(hash, prefix = nil)
        flatten_values(hash, prefix).keys
      end

      def flatten_values(hash, prefix = nil)
        hash.each_with_object({}) do |(key, value), ret|
          name = [prefix, key].compact.join('.')

          if value.is_a?(Hash)
            ret.merge!(flatten_values(value, name))
          else
            ret[name] = value.to_s
          end
        end
      end

      def interpolation_names(value)
        value.to_s.scan(/%\{([a-zA-Z0-9_]+)\}/).flatten.sort
      end

      def deep_sort(value)
        case value
        when Hash
          value.keys.sort.to_h { |key| [key, deep_sort(value[key])] }
        else
          value
        end
      end

      def source_files
        @source_files ||= SCAN_GLOBS.flat_map do |glob|
          Dir[absolute_path(glob)]
        end.reject do |file|
          rel = relative_path(file)
          SCAN_EXCLUDES.any? { |exclude| rel.start_with?(exclude) || rel == exclude }
        end
      end

      def client_source_files
        source_files.reject { |file| relative_path(file).start_with?('servers/ruby/') }
      end

      def server_source_files
        source_files.select { |file| relative_path(file).start_with?('servers/ruby/lib/haveapi/') }
      end

      def used_keys
        @used_keys ||= source_files.flat_map do |file|
          rel = relative_path(file)
          text = File.read(file)

          full_keys = text.scan(FULL_KEY_LITERAL_PATTERN).flatten
          client_keys = if rel.start_with?('clients/')
                          CLIENT_KEY_LITERAL_PATTERNS.flat_map do |pattern|
                            text.scan(pattern).flatten.map { |key| "haveapi_client.#{key}" }
                          end
                        else
                          []
                        end

          full_keys + client_keys
        end.uniq
      end

      def write_file(path, content)
        abs = absolute_path(path)
        FileUtils.mkdir_p(File.dirname(abs))
        File.write(abs, content)
      end

      def absolute_path(path)
        File.join(root, path)
      end

      def relative_path(path)
        path.delete_prefix("#{root}/")
      end
    end
  end
end
