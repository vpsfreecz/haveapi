# frozen_string_literal: true

module I18nSpec
  User = Struct.new(:language)

  class Provider < HaveAPI::Authentication::Basic::Provider
    protected

    def find_user(_request, username, password)
      User.new(:cs) if username == 'user' && password == 'pass'
    end
  end
end

describe HaveAPI::I18n do
  context 'with translated API responses' do
    api do
      define_resource(:Thing) do
        version 1
        auth false
        desc HaveAPI.message('i18n_spec.resources.thing.desc')

        define_action(:Create) do
          route ''
          http_method :post
          desc HaveAPI.message('i18n_spec.resources.thing.actions.create.desc')

          input do
            string :name,
                   label: HaveAPI.message('i18n_spec.resources.thing.params.name.label'),
                   desc: HaveAPI.message('i18n_spec.resources.thing.params.name.desc'),
                   required: true,
                   length: { min: 3, max: 5 }
            string :code, length: {
              min: 3,
              message: HaveAPI.message('haveapi.validators.length.min', min: 3)
            }
            integer :count
          end

          output do
            bool :ok
          end

          authorize { allow }

          def exec
            { ok: true }
          end
        end

        define_action(:CustomError) do
          route 'custom_error'
          http_method :get

          authorize { allow }

          def exec
            error!('plain custom error')
          end
        end
      end
    end

    default_version 1

    it 'keeps default English responses unchanged' do
      header 'Accept', 'application/json'
      call_api(:post, '/v1/things', thing: {})

      expect(api_response.message).to eq('input parameters not valid')
      expect(api_response.errors[:name]).to include('required parameter missing')
      expect(last_response.headers['Vary']).to include('Accept-Language')
    end

    it 'falls back to English for unsupported languages' do
      header 'Accept', 'application/json'
      header 'Accept-Language', 'de'
      get '/unknown_resource'

      expect(api_response.message).to eq('Action not found')
    end

    it 'leaves custom string errors unchanged' do
      header 'Accept', 'application/json'
      header 'Accept-Language', 'en'
      get '/v1/things/custom_error'

      expect(api_response.message).to eq('plain custom error')
    end

    it 'restores the ambient I18n locale after each request' do
      previous_available = ::I18n.available_locales
      previous_locale = ::I18n.locale
      ::I18n.available_locales = (previous_available + [:cs]).uniq
      ::I18n.locale = :cs

      header 'Accept', 'application/json'
      get '/unknown_resource'

      expect(api_response.message).to eq('Action not found')
      expect(::I18n.locale).to eq(:cs)
    ensure
      ::I18n.available_locales = (Array(previous_available) + [previous_locale]).uniq
      ::I18n.locale = previous_locale
      ::I18n.available_locales = previous_available
    end
  end

  context 'with a custom locale header' do
    empty_api
    locale_header 'X-Accept-Language'

    it 'uses the configured header for locale negotiation and Vary' do
      header 'Accept', 'application/json'
      header 'X-Accept-Language', 'en'
      get '/unknown_resource'

      expect(api_response.message).to eq('Action not found')
      expect(last_response.headers['Vary']).to eq('X-Accept-Language')
    end

    it 'allows the configured header in CORS preflight responses' do
      header 'Accept', 'application/json'
      header 'Origin', 'https://example.com'
      header 'Access-Control-Request-Method', 'GET'
      header 'Access-Control-Request-Headers', 'X-Accept-Language'
      options '/'

      allowed_headers = last_response.headers['access-control-allow-headers'].split(',')
      expect(allowed_headers).to include('X-Accept-Language')
    end
  end
end
