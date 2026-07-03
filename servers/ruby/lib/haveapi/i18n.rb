require 'i18n'

module HaveAPI
  class LocalizedMessage
    attr_reader :key, :values, :default

    def initialize(key, default: nil, scope: nil, **values)
      @key = normalize_key(key, scope)
      @default = default
      @values = values
    end

    def translate(extra_values = {})
      values = localized_values(@values.merge(extra_values))
      opts = values
      opts[:default] = @default if @default

      ::I18n.t(@key, **opts)
    end

    def to_s
      translate
    end

    private

    def normalize_key(key, scope)
      return key.to_s unless scope

      "#{scope}.#{key}"
    end

    def localized_values(values)
      values.transform_values do |value|
        case value
        when Array
          value.map { |v| HaveAPI.localize(v) }.join('; ')
        else
          HaveAPI.localize(value)
        end
      end
    end
  end

  module I18n
    class << self
      def setup
        locale_dir = File.expand_path('locales', __dir__)
        ::I18n.load_path |= Dir[File.join(locale_dir, '*.yml')]
      end

      def available_locales
        locale_dir = File.expand_path('locales', __dir__)

        Dir[File.join(locale_dir, '*.yml')].map do |path|
          File.basename(path, '.yml').to_sym
        end.sort
      end

      def accept_language(header, available_locales)
        header.to_s.split(',').each_with_index.filter_map do |raw, index|
          tag, *params = raw.strip.split(';')
          next if tag.nil? || tag.empty?

          q = params.map(&:strip).grep(/\Aq=/).first
          weight = q ? q.split('=', 2).last.to_f : 1.0
          next if weight <= 0.0

          [tag, weight, index]
        end.sort_by { |(_, weight, index)| [-weight, index] }.each do |tag, _, _|
          locale = normalize_locale(tag, available_locales)
          return locale if locale
        end

        nil
      rescue StandardError
        nil
      end

      def normalize_locale(locale, available_locales)
        return if locale.nil?

        tag = locale.to_s.strip.tr('_', '-')
        return if tag.empty? || tag == '*'

        available = Array(available_locales).map(&:to_s)
        candidates = [tag, tag.split('-').first].compact.map(&:downcase).uniq

        candidates.each do |candidate|
          match = available.detect { |v| v.downcase == candidate }
          return match.to_sym if match
        end

        nil
      end
    end
  end

  class << self
    def message(key, default: nil, scope: nil, **values)
      LocalizedMessage.new(key, default:, scope:, **values)
    end

    def t(key, default: nil, scope: nil, **values)
      message(key, default:, scope:, **values).translate
    end

    def localize(value, **extra_values)
      case value
      when LocalizedMessage
        value.translate(extra_values)
      when Array
        value.map { |v| localize(v, **extra_values) }
      when Hash
        value.transform_values { |v| localize(v, **extra_values) }
      when String
        extra_values.empty? ? value : format(value, extra_values)
      else
        value
      end
    end
  end
end

HaveAPI::I18n.setup
