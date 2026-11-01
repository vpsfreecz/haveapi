require 'spec_helper'

RSpec.describe HaveAPI::DocumentationLocale do
  api do
    define_resource(:Thing) do
      version 1
      auth false
      desc HaveAPI.message('documentation_locale_spec.resource')
      define_action(:Show) do
        route ''
        http_method :get
        input { string :query }
        output { string :language }
        authorize { allow }
        def exec
          { language: ::I18n.locale.to_s }
        end
      end
    end
  end

  let(:server) do
    HaveAPI::Server.new(get_opt(:api_module)).tap do |api|
      api.use_version(1)
      api.default_locale = :cs
      api.locale_header = 'X-API-Language'
      api.parameter_i18n_scope = 'documentation_locale_spec'
      api.locale { :cs }
      api.mount('/api/')
    end
  end
  let(:app) { server.app }

  before do
    ::I18n.backend.store_translations(:en, documentation_locale_spec: {
                                      resource: 'English resource',
                                      attributes: { query: { label: 'English query' } }
                                    })
    ::I18n.backend.store_translations(:cs, documentation_locale_spec: {
                                      resource: 'Český prostředek',
                                      attributes: { query: { label: 'Český dotaz' } }
                                    })
  end

  describe '#documentation_t' do
    let(:helper) { Object.new.extend(described_class) }

    it 'preserves translations, interpolation and defaults across repeated locale changes' do
      ::I18n.backend.store_translations(:en, haveapi: { documentation: {
                                        locale_spec_present: 'English %{name}', locale_spec_fallback: 'Fallback %{name}'
                                      } })
      ::I18n.backend.store_translations(:cs, haveapi: { documentation: { locale_spec_present: 'Česky %{name}' } })
      %i[en cs en].each do |locale|
        ::I18n.with_locale(locale) do
          expected = locale == :en ? 'English <&>' : 'Česky <&>'
          expect(helper.documentation_t('locale_spec_present', name: '<&>')).to eq(expected)
          expect(helper.documentation_t('locale_spec_present', default: 'Ignored', name: '<&>')).to eq(expected)
          expect(helper.documentation_t('locale_spec_fallback', name: 'input')).to eq('Fallback input')
          expect(helper.documentation_t('locale_spec_absent', default: 'Default %{name}', name: 'input')).to eq('Default input')
          expect(helper.documentation_t('locale_spec_absent')).to be_nil
          expect(helper.documentation_t('browser')).to eq(::I18n.t('haveapi.documentation.browser'))
        end
      end
    end

    it 'reuses the resolved English fallback without translating the same key twice' do
      allow(::I18n).to receive(:t).and_call_original
      ::I18n.with_locale(:en) do
        expect(helper.documentation_t('labels.language')).to eq('Language')
      end
      expect(::I18n).to have_received(:t).with('haveapi.documentation.labels.language', locale: :en, default: nil).once
      expect(::I18n).to have_received(:t).once
    end

    context 'with a documentation render scope' do
      let(:helper) do
        Class.new do
          attr_accessor :scope_locale

          def settings = self
          def api_server = self
          def documentation_locale = scope_locale
          def activate_locale(locale) = (::I18n.locale = locale)
          def add_vary_header(_header); end
        end.include(described_class).new.tap { |instance| instance.scope_locale = :en }
      end

      before do
        ::I18n.backend.store_translations(:en, haveapi: { documentation: {
                                          memo_static: 'English label', memo_interpolated: 'Hello %{name}',
                                          memo_fallback: 'English fallback', memo_hash: { leaf: 'Leaf' }, memo_number: 7
                                        } })
        ::I18n.backend.store_translations(:cs, haveapi: { documentation: { memo_static: 'Český štítek' } })
        allow(::I18n).to receive(:t).and_call_original
      end

      it 'memoizes static strings by active locale, including explicit nil defaults and English fallback' do
        helper.with_documentation_locale(persist: false) do
          %i[en cs en].each do |locale|
            ::I18n.with_locale(locale) do
              expected = locale == :en ? 'English label' : 'Český štítek'
              expect(helper.documentation_t('memo_static', default: nil)).to eq(expected)
              expect(helper.documentation_t('memo_static')).to eq(expected)
            end
          end
          ::I18n.with_locale(:cs) do
            2.times { expect(helper.documentation_t('memo_fallback')).to eq('English fallback') }
          end
        end

        expect(::I18n).to have_received(:t).with('haveapi.documentation.memo_static', locale: :en, default: nil).twice
        expect(::I18n).to have_received(:t).with('haveapi.documentation.memo_static', default: 'English label').once
        expect(::I18n).to have_received(:t).with('haveapi.documentation.memo_fallback', locale: :en, default: nil).once
        expect(::I18n).to have_received(:t).with('haveapi.documentation.memo_fallback', default: 'English fallback').once
      end

      it 'isolates caller mutation of both the initial result and later hit copies' do
        helper.with_documentation_locale(persist: false) do
          first = helper.documentation_t('memo_static')
          first.replace('Changed first result')
          hit = helper.documentation_t('memo_static')
          expect(hit).to eq('English label')
          expect(hit).not_to be_frozen
          hit.replace('Changed hit')
          expect(helper.documentation_t('memo_static')).to eq('English label')
        end
        expect(::I18n).to have_received(:t).with('haveapi.documentation.memo_static', locale: :en, default: nil).once
      end

      it 'keeps explicit defaults, interpolation and non-String keys on the original lookup path' do
        helper.with_documentation_locale(persist: false) do
          2.times do
            expect(helper.documentation_t('memo_default_only', default: 'Explicit default')).to eq('Explicit default')
            expect(helper.documentation_t(:memo_static)).to eq('English label')
          end
          %w[first second].each do |name|
            expect(helper.documentation_t('memo_interpolated', name:)).to eq("Hello #{name}")
          end
        end

        expect(::I18n).to have_received(:t).with('haveapi.documentation.memo_default_only', locale: :en, default: 'Explicit default').twice
        expect(::I18n).to have_received(:t).with('haveapi.documentation.memo_static', locale: :en, default: nil).twice
        expect(::I18n).to have_received(:t).with('haveapi.documentation.memo_interpolated', locale: :en, default: nil, name: 'first').once
        expect(::I18n).to have_received(:t).with('haveapi.documentation.memo_interpolated', locale: :en, default: nil, name: 'second').once
      end

      it 'does not retain missing, hash or other non-String results' do
        helper.with_documentation_locale(persist: false) do
          2.times do
            expect(helper.documentation_t('memo_late')).to be_nil
            expect(helper.documentation_t('memo_hash')).to eq(leaf: 'Leaf')
            expect(helper.documentation_t('memo_number')).to eq(7)
          end
          ::I18n.backend.store_translations(:en, haveapi: { documentation: { memo_late: 'Now available' } })
          expect(helper.documentation_t('memo_late')).to eq('Now available')
        end

        expect(::I18n).to have_received(:t).with('haveapi.documentation.memo_late', locale: :en, default: nil).exactly(3).times
        expect(::I18n).to have_received(:t).with('haveapi.documentation.memo_hash', locale: :en, default: nil).twice
        expect(::I18n).to have_received(:t).with('haveapi.documentation.memo_number', locale: :en, default: nil).twice
      end

      it 'starts fresh on each render and leaves no memo outside that scope' do
        helper.with_documentation_locale(persist: false) { expect(helper.documentation_t('memo_static')).to eq('English label') }
        ::I18n.backend.store_translations(:en, haveapi: { documentation: { memo_static: 'Next render' } })
        helper.with_documentation_locale(persist: false) { expect(helper.documentation_t('memo_static')).to eq('Next render') }
        ::I18n.backend.store_translations(:en, haveapi: { documentation: { memo_static: 'Outside render' } })
        ::I18n.with_locale(:en) { expect(helper.documentation_t('memo_static')).to eq('Outside render') }
      end

      it 'clears nested scopes after errors and restores the active locale' do
        previous = ::I18n.locale
        helper.scope_locale = :cs
        helper.with_documentation_locale(persist: false) do
          expect(helper.documentation_t('memo_static')).to eq('Český štítek')
          helper.scope_locale = :en
          expect do
            helper.with_documentation_locale(persist: false) do
              expect(helper.documentation_t('memo_static')).to eq('English label')
              raise 'nested rendering failed'
            end
          end.to raise_error(RuntimeError, 'nested rendering failed')
          expect(::I18n.locale).to eq(:cs)
          ::I18n.backend.store_translations(:cs, haveapi: { documentation: { memo_static: 'After inner scope' } })
          expect(helper.documentation_t('memo_static')).to eq('After inner scope')
        end
        expect(::I18n.locale).to eq(previous)

        helper.scope_locale = :en
        expect do
          helper.with_documentation_locale(persist: false) do
            expect(helper.documentation_t('memo_static')).to eq('English label')
            raise 'outer rendering failed'
          end
        end.to raise_error(RuntimeError, 'outer rendering failed')
        ::I18n.backend.store_translations(:en, haveapi: { documentation: { memo_static: 'After aborted render' } })
        ::I18n.with_locale(:en) { expect(helper.documentation_t('memo_static')).to eq('After aborted render') }
        expect(::I18n.locale).to eq(previous)
      end

      it 'does not memoize a failed lookup' do
        calls = 0
        allow(::I18n).to receive(:t).with('haveapi.documentation.memo_failure', locale: :en, default: nil) do
          calls += 1
          raise 'lookup failed' if calls == 1

          'Recovered label'
        end
        helper.with_documentation_locale(persist: false) do
          expect { helper.documentation_t('memo_failure') }.to raise_error(RuntimeError, 'lookup failed')
          2.times { expect(helper.documentation_t('memo_failure')).to eq('Recovered label') }
        end
        expect(calls).to eq(2)
      end
    end
  end

  def document_language
    last_response.body[/<html lang="([^"]+)"/, 1]
  end

  def index_url
    CGI.unescapeHTML(last_response.body[/data-search-index-url="([^"]+)"/, 1])
  end

  it 'negotiates browser preferences independently of API configuration without saving detection' do
    { 'CS-cz, en;q=0.8' => 'cs', 'de, en-GB;q=0.8,cs;q=0.5' => 'en',
      'en;q=0,cs-CZ;q=0.7' => 'cs', 'en-US,cs;q=0.9' => 'en',
      'de,*;q=0.5' => 'en', '*' => 'en', '' => 'en' }.each do |browser, expected|
      get '/api/v1/', {}, 'HTTP_ACCEPT_LANGUAGE' => browser, 'HTTP_X_API_LANGUAGE' => 'cs'
      expect(last_response).to be_ok
      expect(document_language).to eq(expected), browser
      expect(last_response.headers['Set-Cookie'].to_s).not_to include('haveapi.docs.locale')
    end
  end

  it 'saves only explicit choices and gives a valid query priority over the saved language' do
    get '/api/v1/?resource=thing&doc_lang=cs', {}, 'HTTP_ACCEPT_LANGUAGE' => 'en'
    expect(document_language).to eq('cs')
    cookie = last_response.headers['Set-Cookie'].to_s
    expect(cookie).to include('haveapi.docs.locale=cs', 'path=/api/', 'samesite=lax')
    expect(cookie.downcase).not_to include('domain=', 'secure')
    get '/api/v1/', {}, 'HTTP_ACCEPT_LANGUAGE' => 'en'
    expect(document_language).to eq('cs')
    get '/api/v1/?doc_lang=en', {}, 'HTTP_ACCEPT_LANGUAGE' => 'cs'
    expect(document_language).to eq('en')
    expect(last_response.headers['Set-Cookie'].to_s).to include('haveapi.docs.locale=en')
  end

  it 'uses a secure host-only cookie over HTTPS and works without returning that cookie' do
    get 'https://example.org/api/v1/?doc_lang=cs'
    expect(document_language).to eq('cs')
    expect(last_response.headers['Set-Cookie'].to_s).to include('secure')
    clear_cookies
    get '/api/v1/?doc_lang=cs'
    expect(document_language).to eq('cs')
    clear_cookies
    get '/api/v1/'
    expect(document_language).to eq('en')
  end

  it 'ignores unsupported, nested and duplicate preferences' do
    set_cookie 'haveapi.docs.locale=unknown; path=/api/'
    %w[doc_lang=unknown doc_lang=auto doc_lang[]=cs doc_lang=cs&doc_lang=en].each do |query|
      get "/api/v1/?#{query}", {}, 'HTTP_ACCEPT_LANGUAGE' => 'en'
      expect(document_language).to eq('en')
      expect(last_response.headers['Set-Cookie'].to_s).not_to include('haveapi.docs.locale')
    end
  end

  it 'localizes metadata and controls, retaining the exact language choices above Theme' do
    get '/api/v1/?resource=thing&doc_lang=cs&q=dotaz'
    body = last_response.body
    expect(body).to include('Český prostředek', 'Český dotaz', 'data-documentation-language', '>English</option>', '>Česky</option>')
    expect(body.index('data-documentation-language')).to be < body.index('docs-theme-label')
    expect(body).to include('name="resource" value="thing"', 'name="q" value="dotaz"')
    expect(body).not_to include('value="auto"')
  end

  it 'pins search to the displayed locale without persisting a read-only selector' do
    get '/api/v1/?resource=thing&doc_lang=cs'
    endpoint = index_url
    expect(endpoint).to include('doc_lang=cs')
    clear_cookies
    get endpoint, {}, 'HTTP_ACCEPT_LANGUAGE' => 'en'
    expect(last_response).to be_ok
    expect(last_response.body).to include('"locale":"cs"', 'Český dotaz')
    expect(last_response.headers['Set-Cookie'].to_s).not_to include('haveapi.docs.locale')
    expect(last_response.headers['Cache-Control']).to eq('private, max-age=86400, immutable')
    expect(last_response.headers['Vary']).to include('Cookie', 'Accept-Language', 'Authorization')
    get endpoint.sub('doc_lang=cs', 'doc_lang=en')
    expect(last_response.status).to eq(409)
  end

  it 'preserves executable examples across UI locales' do
    rendered = %w[en cs].map do |locale|
      get "/api/v1/?doc_lang=#{locale}"
      last_response.body.scan(%r{<pre><code[^>]*>(.*?)</code></pre>}m).flatten
    end
    expect(rendered.first).not_to be_empty
    expect(rendered.last).to eq(rendered.first)
  end

  it 'leaves ordinary actions and OPTIONS in the configured API locale' do
    set_cookie 'haveapi.docs.locale=cs; path=/api/'
    get '/api/v1/things?doc_lang=cs', {}, 'HTTP_X_API_LANGUAGE' => 'en'
    expect(JSON.parse(last_response.body).dig('response', 'thing', 'language')).to eq('en')
    options '/api/v1/?doc_lang=cs', {}, 'HTTP_X_API_LANGUAGE' => 'en'
    expect(last_response.body).to include('English resource', 'English query')
    expect(last_response.body).not_to include('Český prostředek')
  end

  it 'restores the thread locale after successful and failed documentation rendering' do
    previous = ::I18n.locale
    get '/api/v1/?doc_lang=cs'
    expect(::I18n.locale).to eq(previous)
    allow(server).to receive(:describe_version) do
      expect(::I18n.locale).to eq(:cs)
      raise 'description failure'
    end
    app.set :raise_errors, true
    expect { get '/api/v1/?doc_lang=cs' }.to raise_error(RuntimeError, 'description failure')
    expect(::I18n.locale).to eq(previous)
  end

  it 'uses localized articles and stable mounted links with explicit English fallback' do
    get '/api/doc/protocol?doc_lang=cs'
    expect(document_language).to eq('cs')
    expect(last_response.body).to include('id="resources"', 'src="/api/doc/protocol.png"', 'href="/api/doc/typed-input-validation')
    get '/api/doc/documentation-ui'
    expect(document_language).to eq('cs')
    expect(last_response.body).to include('lang="en"', 'Browsing API documentation')
    get '/api/doc/protocol.md'
    expect(last_response).to be_ok
    get '/api/doc/../../Gemfile'
    expect(last_response.status).to eq(404)
  end
end
