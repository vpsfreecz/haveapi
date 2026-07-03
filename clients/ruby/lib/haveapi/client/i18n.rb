require 'yaml'

module HaveAPI::Client
  module I18n
    DEFAULT_LOCALE = :en
    DEFAULT_LANGUAGE_HEADER = 'Accept-Language'.freeze
    HEADER_NAME = /\A[A-Za-z0-9!#$%&'*+\-.^_`|~]+\z/
    HEADER_VALUE_UNSAFE = /[\x00\r\n]/

    class << self
      def t(language, key, values = {})
        message = lookup(locale_for(language), key) || lookup(DEFAULT_LOCALE, key) || key.to_s

        interpolate(message, values)
      end

      def request_headers(language, language_header = DEFAULT_LANGUAGE_HEADER)
        return {} if language.nil? || language.to_s.empty?

        assert_header_name!(language_header)
        assert_header_value!(language)

        { language_header => language.to_s }
      end

      def locale_for(language)
        return DEFAULT_LOCALE if language.nil? || language.to_s.empty?

        parse_accept_language(language).each do |tag|
          normalized = normalize_locale(tag)
          return normalized if normalized && messages.has_key?(normalized)
        end

        DEFAULT_LOCALE
      end

      def assert_header_name!(header)
        return if header.is_a?(String) && header.match?(HEADER_NAME)

        raise ArgumentError, "invalid language HTTP header name: #{header.inspect}"
      end

      def assert_header_value!(value)
        return if value.is_a?(String) && !value.match?(HEADER_VALUE_UNSAFE)

        raise ArgumentError, "invalid language HTTP header value: #{value.inspect}"
      end

      private

      def lookup(locale, key)
        key.to_s.sub(/\Ahaveapi_client\./, '').split('.').reduce(messages[locale]) do |data, part|
          break unless data.is_a?(Hash)

          data[part]
        end
      end

      def interpolate(message, values)
        values.reduce(message.dup) do |ret, (key, value)|
          ret.gsub("%{#{key}}", value.to_s)
        end
      end

      def parse_accept_language(header)
        header.to_s.split(',').filter_map do |part|
          tag, *params = part.split(';')
          q = 1.0

          params.each do |param|
            name, value = param.split('=', 2).map(&:strip)
            q = value.to_f if name == 'q'
          end

          next if tag.strip.empty? || q <= 0

          [tag.strip, q]
        end.sort_by { |(_tag, q)| -q }.map(&:first)
      end

      def normalize_locale(tag)
        normalized = tag.to_s.strip.tr('_', '-').sub(/\..*\z/, '').downcase
        return if normalized.empty?

        primary = normalized.split('-', 2).first.to_sym
        primary if messages.has_key?(primary)
      end

      def messages
        @messages ||= begin
          dir = File.expand_path('locales', __dir__)

          Dir[File.join(dir, '*.yml')].to_h do |file|
            locale = File.basename(file, '.yml').to_sym
            data = YAML.safe_load_file(file, aliases: true) || {}

            [locale, data.fetch(locale.to_s).fetch('haveapi_client')]
          end
        end
      end
    end
  end
end
