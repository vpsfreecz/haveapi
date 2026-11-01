require 'uri'

module HaveAPI
  # Documentation has its own preference; API request locale remains independent.
  module DocumentationLocale
    LOCALES = %w[en cs].freeze
    COOKIE = 'haveapi.docs.locale'.freeze

    def documentation_locale
      @documentation_locale ||= begin
        explicit = documentation_locale_override
        saved = request.cookies[COOKIE]
        explicit || (saved if LOCALES.include?(saved)) ||
          HaveAPI::I18n.accept_language(request.env['HTTP_ACCEPT_LANGUAGE'], LOCALES)&.to_s || 'en'
      end
    end

    def documentation_locale_override
      pairs = URI.decode_www_form(request.query_string)
      values = pairs.select { |pair| pair.first == 'doc_lang' }
      values.first.last if values.length == 1 && LOCALES.include?(values.first.last)
    rescue ArgumentError
      nil
    end

    def with_documentation_locale(persist: true)
      previous = ::I18n.locale
      @documentation_static_messages = {}
      settings.api_server.activate_locale(documentation_locale)
      add_vary_header('Accept-Language')
      add_vary_header('Cookie')
      if persist && documentation_locale_override && !documentation_search_index_request?
        response.set_cookie(COOKIE, value: documentation_locale, path: root,
                                    max_age: 31_536_000, same_site: :lax, secure: base_url.start_with?('https:'))
      end
      yield
    ensure
      @documentation_static_messages = nil
      ::I18n.locale = previous
    end

    def documentation_language_parameters
      URI.decode_www_form(request.query_string).reject { |pair| pair.first == 'doc_lang' }
    rescue ArgumentError
      []
    end

    def documentation_t(key, default: nil, **values)
      if @documentation_static_messages && key.is_a?(String) && default.nil? && values.empty?
        memo = (@documentation_static_messages[::I18n.locale] ||= {})
        cached = memo[key]
        return cached.dup if cached
      end

      full_key = "haveapi.documentation.#{key}"
      fallback = ::I18n.t(full_key, locale: :en, default:, **values)
      result = ::I18n.locale == :en ? fallback : ::I18n.t(full_key, default: fallback, **values)

      # Own the stored bytes; neither the first result nor later hit copies can
      # mutate labels used elsewhere in this request. Dynamic lookups stay live.
      memo[key] = result.dup.freeze if memo && result.is_a?(String)
      result
    end
  end
end
