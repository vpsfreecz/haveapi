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

    it 'localizes validation messages using Accept-Language' do
      header 'Accept', 'application/json'
      header 'Accept-Language', 'cs'
      call_api(:post, '/v1/things', thing: { count: 'nope' })

      expect(api_response.message).to eq('vstupní parametry nejsou platné')
      expect(api_response.errors[:name]).to include('povinný parametr chybí')
      expect(api_response.errors[:count].first).to include('neplatné celé číslo')
      expect(last_response.headers['Vary']).to include('Accept-Language')
    end

    it 'normalizes regional language tags' do
      header 'Accept', 'application/json'
      header 'Accept-Language', 'cs-CZ,cs;q=0.9,en;q=0.5'
      get '/unknown_resource'

      expect(api_response.message).to eq('Akce nebyla nalezena')
    end

    it 'falls back to English for unsupported languages' do
      header 'Accept', 'application/json'
      header 'Accept-Language', 'de'
      get '/unknown_resource'

      expect(api_response.message).to eq('Action not found')
    end

    it 'localizes validator descriptions in OPTIONS responses' do
      header 'Accept', 'application/json'
      header 'Accept-Language', 'cs'
      options '/v1/things', method: 'POST'

      length = api_response[:input][:parameters][:name][:validators][:length]
      expect(length[:message]).to eq('délka musí být v rozsahu <3, 5>')
    end

    it 'localizes API metadata in OPTIONS responses' do
      previous_available = ::I18n.available_locales
      ::I18n.available_locales = (previous_available + %i[en cs]).uniq
      ::I18n.backend.store_translations(
        :en,
        i18n_spec: {
          resources: {
            thing: {
              desc: 'Manage things',
              actions: { create: { desc: 'Create a thing' } },
              params: {
                name: {
                  label: 'Name',
                  desc: 'Thing name'
                }
              }
            }
          }
        }
      )
      ::I18n.backend.store_translations(
        :cs,
        i18n_spec: {
          resources: {
            thing: {
              desc: 'Spravovat věci',
              actions: { create: { desc: 'Vytvořit věc' } },
              params: {
                name: {
                  label: 'Název',
                  desc: 'Název věci'
                }
              }
            }
          }
        }
      )

      header 'Accept', 'application/json'
      header 'Accept-Language', 'cs'
      call_api(:options, '/?describe=default')

      resource = api_response[:resources][:thing]
      action = resource[:actions][:create]
      param = action[:input][:parameters][:name]

      expect(resource[:description]).to eq('Spravovat věci')
      expect(action[:description]).to eq('Vytvořit věc')
      expect(param[:label]).to eq('Název')
      expect(param[:description]).to eq('Název věci')
    ensure
      ::I18n.available_locales = previous_available
    end

    it 'localizes application-supplied lazy validator messages' do
      header 'Accept', 'application/json'
      header 'Accept-Language', 'cs'
      call_api(:post, '/v1/things', thing: { name: 'abc', code: 'x' })

      expect(api_response.errors[:code]).to include('délka musí být alespoň 3')
    end

    it 'leaves custom string errors unchanged' do
      header 'Accept', 'application/json'
      header 'Accept-Language', 'cs'
      get '/v1/things/custom_error'

      expect(api_response.message).to eq('plain custom error')
    end

    it 'works when host applications constrain global I18n locales' do
      previous_available = ::I18n.available_locales
      previous_locale = ::I18n.locale
      ::I18n.available_locales = [:en]

      header 'Accept', 'application/json'
      header 'Accept-Language', 'cs'
      get '/unknown_resource'

      expect(api_response.message).to eq('Akce nebyla nalezena')
    ensure
      ::I18n.available_locales = (Array(previous_available) + [previous_locale]).uniq
      ::I18n.locale = previous_locale
      ::I18n.available_locales = previous_available
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

    it 'localizes nested message values without changing surrounding structure' do
      previous_locale = ::I18n.locale
      ::I18n.locale = :cs

      data = {
        message: HaveAPI.message('haveapi.errors.action_not_found'),
        errors: {
          name: [HaveAPI.message('haveapi.validation.required_parameter_missing')]
        }
      }

      expect(HaveAPI.localize(data)).to eq({
                                             message: 'Akce nebyla nalezena',
                                             errors: {
                                               name: ['povinný parametr chybí']
                                             }
                                           })
    ensure
      ::I18n.locale = previous_locale
    end
  end

  context 'with a locale resolver' do
    empty_api

    locale do |**_|
      :cs
    end

    it 'uses the resolver when no language is requested explicitly' do
      header 'Accept', 'application/json'
      get '/unknown_resource'

      expect(api_response.message).to eq('Akce nebyla nalezena')
    end

    it 'does not use the resolver when an unsupported language is requested explicitly' do
      ['de', '%%%'].each do |language|
        header 'Accept', 'application/json'
        header 'Accept-Language', language
        get '/unknown_resource'

        expect(api_response.message).to eq('Action not found')
      end
    end
  end

  context 'with an authenticated locale resolver' do
    api do
      define_resource(:Thing) do
        version 1
        auth false

        define_action(:Create) do
          route ''
          http_method :post

          input do
            string :name, required: true, length: { min: 3, max: 5 }
          end

          authorize { allow }
        end
      end
    end

    default_version 1
    auth_chain I18nSpec::Provider

    locale do |current_user:, default_locale:, **_|
      current_user&.language || default_locale
    end

    it 'uses the authenticated user for root self-description locale fallback' do
      login('user', 'pass')
      header 'Accept', 'application/json'
      call_api(:options, '/?describe=default')

      action = api_response[:resources][:thing][:actions][:create]
      length = action.dig(:input, :parameters, :name, :validators, :length)
      expect(length[:message]).to eq('délka musí být v rozsahu <3, 5>')
    end
  end

  context 'with a custom locale header' do
    empty_api
    locale_header 'X-Accept-Language'

    it 'uses the configured header for locale negotiation and Vary' do
      header 'Accept', 'application/json'
      header 'X-Accept-Language', 'cs'
      get '/unknown_resource'

      expect(api_response.message).to eq('Akce nebyla nalezena')
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
