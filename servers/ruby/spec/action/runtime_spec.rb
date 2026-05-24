# frozen_string_literal: true

describe HaveAPI::Action do
  describe 'runtime' do
    api do
      define_resource(:Test) do
        version 1
        auth false

        define_action(:Echo) do
          http_method :post
          authorize { allow }

          class << self
            attr_accessor :calls
          end
          self.calls = []

          input do
            string :msg
          end

          output do
            string :msg
          end

          def exec
            self.class.calls << :exec
            { msg: input[:msg] }
          end
        end

        define_action(:OptionalShape) do
          route 'optional_shape'
          http_method :post
          authorize { allow }

          input do
            string :label
          end

          output do
            bool :ok
          end

          def exec
            { ok: true }
          end
        end

        define_action(:Batch) do
          route 'batch'
          http_method :post
          authorize { allow }

          input(:hash_list) do
            string :label, required: true
          end

          meta(:global) do
            input do
              bool :confirmed, required: true
            end
          end

          output(:hash) do
            integer :count
          end

          def exec
            { count: input.size }
          end
        end

        define_action(:OutputOnlyObjectMeta) do
          route 'output_only_object_meta'
          http_method :post
          authorize { allow }

          input do
            string :msg
          end

          meta(:object) do
            output do
              string :etag
            end
          end

          output do
            string :msg
          end

          def exec
            { msg: input[:msg] }
          end
        end

        define_action(:DigitPath) do
          route 'ipv4/{ip4_id}'
          http_method :get

          authorize do |_user, path_params|
            deny if path_params['ip4_id'] == '1'

            allow
          end

          output do
            string :value
          end

          def exec
            { value: 'ok' }
          end
        end

        define_action(:ColonPath) do
          route 'accounts/:account_id/secret'
          http_method :get

          authorize do |_user, path_params|
            deny unless path_params['account_id'] == '1'

            allow
          end

          output do
            string :value
          end

          def exec
            { value: path_params['account_id'] }
          end
        end

        define_action(:BodyShadow) do
          route 'profiles/{profile_id}'
          http_method :put

          authorize do |_user, path_params|
            deny unless path_params['profile_id'] == '2'

            allow
          end

          input do
            string :name
          end

          output do
            string :route_profile_id
          end

          def exec
            { route_profile_id: path_params['profile_id'] }
          end
        end

        define_action(:FilteredDefault) do
          route 'filtered_default'
          http_method :post

          authorize do
            input blacklist: [:admin]
            allow
          end

          input do
            string :name
            bool :admin, default: true, fill: true
          end

          output do
            bool :saw_admin
            bool :admin
          end

          def exec
            { saw_admin: input.has_key?(:admin), admin: input[:admin] }
          end
        end

        define_action(:MetadataInput) do
          route 'metadata_input'
          http_method :post

          authorize do
            input blacklist: [:confirmed]
            allow
          end

          meta(:global) do
            input do
              bool :confirmed
            end
          end

          output do
            bool :saw_confirmed
          end

          def exec
            { saw_confirmed: meta.has_key?(:confirmed) }
          end
        end

        define_action(:MetadataOutput) do
          route 'metadata_output'
          http_method :post

          authorize do
            output blacklist: [:secret_status]
            allow
          end

          meta(:global) do
            output do
              string :public_status
              string :secret_status
            end
          end

          output do
            bool :ok
          end

          def exec
            set_meta(public_status: 'queued', secret_status: 'internal-token')
            { ok: true }
          end
        end

        define_action(:MetadataSpecificOutput) do
          route 'metadata_specific_output'
          http_method :post

          authorize do
            output whitelist: [:ok]
            meta_output blacklist: [:secret_status]
            allow
          end

          meta(:global) do
            output do
              string :public_status
              string :secret_status
            end
          end

          output do
            bool :ok
            string :hidden_body
          end

          def exec
            set_meta(public_status: 'queued', secret_status: 'internal-token')
            { ok: true, hidden_body: 'body-secret' }
          end
        end

        define_action(:WhitelistedIndex, superclass: HaveAPI::Actions::Default::Index) do
          route 'whitelisted'

          authorize do
            output whitelist: [:name]
            allow
          end

          output(:hash_list) do
            string :name
            string :secret
          end

          def count
            2
          end

          def exec
            [
              { name: 'one', secret: 'hidden' },
              { name: 'two', secret: 'hidden' }
            ]
          end
        end

        define_action(:UnnamespacedInput) do
          route 'unnamespaced_input'
          http_method :post

          authorize do
            input blacklist: [:secret]
            allow
          end

          input(:hash, namespace: false) do
            string :public
            string :secret
          end

          output do
            bool :has_params_method
            bool :input_saw_secret
          end

          def exec
            {
              has_params_method: respond_to?(:params),
              input_saw_secret: input.has_key?(:secret)
            }
          end
        end

        define_action(:UnnamespacedPathInput) do
          route 'unnamespaced_input/{test_id}'
          http_method :put
          authorize { allow }

          input(:hash, namespace: false) do
            string :public
            string :test_id
          end

          output do
            bool :input_saw_test_id
            string :input_test_id, nullable: true
            string :path_test_id
          end

          def exec
            {
              input_saw_test_id: input.has_key?(:test_id),
              input_test_id: input[:test_id],
              path_test_id: path_params['test_id']
            }
          end
        end

        define_action(:QueryPathInput) do
          route 'query_input/{test_id}'
          http_method :get
          authorize { allow }

          input(:hash, namespace: false) do
            string :filter
            string :test_id
          end

          output do
            bool :has_params_method
            bool :input_saw_test_id
            string :filter
            string :path_test_id
          end

          def exec
            {
              has_params_method: respond_to?(:params),
              input_saw_test_id: input.has_key?(:test_id),
              filter: input[:filter],
              path_test_id: path_params['test_id']
            }
          end
        end

        define_action(:TopLevelBody) do
          route 'top_level_body'
          http_method :post

          authorize do
            input blacklist: [:secret]
            allow
          end

          input do
            string :public
            string :secret
          end

          output do
            bool :has_params_method
            bool :input_saw_secret
          end

          def exec
            {
              has_params_method: respond_to?(:params),
              input_saw_secret: input.has_key?(:secret)
            }
          end
        end

        define_action(:CustomPayload) do
          route 'custom_payload'
          http_method :post
          authorize { allow }

          input do
            custom :payload
          end

          output do
            bool :top_string_key
            bool :top_symbol_key
            bool :nested_string_key
            bool :nested_symbol_key
          end

          def exec
            payload = input[:payload]
            nested = payload['response']

            {
              top_string_key: payload.has_key?('rawId'),
              top_symbol_key: payload.has_key?(:rawId),
              nested_string_key: nested.has_key?('clientDataJSON'),
              nested_symbol_key: nested.has_key?(:clientDataJSON)
            }
          end
        end

        define_action(:CustomPayloadSymbols) do
          route 'custom_payload_symbols'
          http_method :post
          authorize { allow }

          input do
            custom :payload, symbolize_keys: true
          end

          output do
            bool :top_string_key
            bool :top_symbol_key
            bool :nested_string_key
            bool :nested_symbol_key
          end

          def exec
            payload = input[:payload]
            nested = payload[:response]

            {
              top_string_key: payload.has_key?('rawId'),
              top_symbol_key: payload.has_key?(:rawId),
              nested_string_key: nested.has_key?('clientDataJSON'),
              nested_symbol_key: nested.has_key?(:clientDataJSON)
            }
          end
        end

        define_action(:Closed) do
          route 'closed'
          http_method :post
          auth false

          output do
            bool :ok
          end

          def exec
            { ok: true }
          end
        end

        define_action(:Show) do
          route '{test_id}'
          http_method :get
          authorize { allow }

          output do
            string :id
          end

          def exec
            { id: path_params['test_id'] }
          end
        end

        define_action(:Order) do
          http_method :post
          authorize { allow }

          class << self
            attr_accessor :calls
          end
          self.calls = []

          output do
            bool :ok
          end

          def prepare
            self.class.calls << :prepare
          end

          def pre_exec
            self.class.calls << :pre_exec
          end

          def exec
            self.class.calls << :exec
            { ok: true }
          end
        end

        define_action(:Abort) do
          http_method :post
          authorize { allow }

          class << self
            attr_accessor :calls
          end
          self.calls = []

          output do
            bool :ok
          end

          def exec
            self.class.calls << :exec
            error!('nope')
            self.class.calls << :after_error
            { ok: true }
          end
        end

        define_action(:Boom) do
          http_method :post
          authorize { allow }

          class << self
            attr_accessor :calls
          end
          self.calls = []

          output do
            bool :ok
          end

          def exec
            self.class.calls << :exec
            raise 'boom'
          end
        end

        define_action(:Block) do
          http_method :post
          authorize { allow }
          blocking true

          class << self
            attr_accessor :calls
          end
          self.calls = []

          output do
            bool :ok
          end

          def exec
            self.class.calls << :exec
            { ok: true }
          end

          def state_id
            nil
          end
        end
      end
    end

    default_version 1

    def action_class(name)
      action, = find_action(1, :Test, name)
      action
    end

    def with_exec_exception_hook
      hooks = HaveAPI::Hooks.hooks
      action_hooks = hooks[HaveAPI::Action][:exec_exception]
      original = action_hooks[:listeners].dup

      HaveAPI::Action.connect_hook(:exec_exception) do |ret, _context, e|
        ret[:status] = false
        ret[:message] = e.message
        ret[:http_status] = 422
        ret
      end

      yield
    ensure
      action_hooks[:listeners] = original
    end

    it 'builds path params with string and symbol keys' do
      expect(action_class(:show).path_params('/tests/{test_id}', 123)).to eq({
        'test_id' => '123',
        test_id: '123'
      })
    end

    it '_meta.no suppresses metadata' do
      action_class(:echo).calls.clear

      call_api([:Test], :echo, { test: { msg: 'hi' }, _meta: { no: true } })

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response.response).to have_key(:test)
      expect(api_response.response).not_to have_key(:_meta)

      call_api([:Test], :echo, { test: { msg: 'hi' }, _meta: { no: false } })

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response.response).to have_key(:_meta)
    end

    it 'rejects optional-only input namespaces with invalid shapes' do
      call_api([:Test], :optional_shape, { test: 'not-a-hash' })

      expect(last_response.status).to eq(400)
      expect(api_response).not_to be_ok
      expect(api_response.message).to eq('invalid input layout')
    end

    it 'rejects list inputs with invalid element shapes' do
      call_api([:Test], :batch, { tests: ['not-a-hash'], _meta: { confirmed: true } })

      expect(last_response.status).to eq(400)
      expect(api_response).not_to be_ok
      expect(api_response.message).to eq('invalid input layout')
    end

    it 'validates global metadata on list input actions' do
      call_api([:Test], :batch, { tests: [{ label: 'one' }] })

      expect(last_response.status).to eq(400)
      expect(api_response).not_to be_ok
      expect(api_response.errors[:confirmed]).to include('required parameter missing')

      call_api([:Test], :batch, { tests: [{ label: 'one' }], _meta: { confirmed: 'maybe' } })

      expect(last_response.status).to eq(400)
      expect(api_response).not_to be_ok
      expect(api_response.errors[:confirmed].first).to include('not a valid boolean')
    end

    it 'rejects malformed metadata namespaces' do
      call_api([:Test], :echo, { test: { msg: 'hi' }, _meta: 'not-a-hash' })

      expect(last_response.status).to eq(400)
      expect(api_response).not_to be_ok
      expect(api_response.message).to eq('invalid input layout')
    end

    it 'ignores object metadata definitions without input' do
      call_api([:Test], :output_only_object_meta, {
        test: {
          msg: 'hi',
          _meta: {
            etag: 'client-value'
          }
        }
      })

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response[:test][:msg]).to eq('hi')
    end

    it 'uses path parameters containing digits for authorization' do
      get '/v1/tests/ipv4/1', {}, input: ''

      expect(last_response.status).to eq(403)
      expect(api_response).not_to be_ok
    end

    it 'uses colon-style route parameters for authorization' do
      get '/v1/tests/accounts/2/secret', {}, input: ''

      expect(last_response.status).to eq(403)
      expect(api_response).not_to be_ok
    end

    it 'does not let JSON body keys shadow route parameters for authorization' do
      call_api(:put, '/v1/tests/profiles/1', {
        profile_id: '2',
        test: {
          name: 'attacker'
        }
      })

      expect(last_response.status).to eq(403)
      expect(api_response).not_to be_ok
    end

    it 'does not reintroduce filtered input defaults' do
      call_api([:Test], :filtered_default, { test: { name: 'acct' } })

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response[:test][:saw_admin]).to be(false)
    end

    it 'applies input authorization filters to metadata input' do
      call_api([:Test], :metadata_input, { _meta: { confirmed: true } })

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response[:test][:saw_confirmed]).to be(false)
    end

    it 'applies output authorization filters to global metadata' do
      call_api([:Test], :metadata_output, {})

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response.response[:_meta]).to include(public_status: 'queued')
      expect(api_response.response[:_meta]).not_to have_key(:secret_status)
    end

    it 'applies metadata-specific output filters to global metadata' do
      call_api([:Test], :metadata_specific_output, {})

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response[:test]).to include(ok: true)
      expect(api_response[:test]).not_to have_key(:hidden_body)
      expect(api_response.response[:_meta]).to include(public_status: 'queued')
      expect(api_response.response[:_meta]).not_to have_key(:secret_status)
    end

    it 'keeps global metadata when body output uses a whitelist' do
      get '/v1/tests/whitelisted', { _meta: { count: true } }, input: ''

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response.response[:_meta]).to include(total_count: 2)
    end

    it 'filters unnamespaced input without exposing legacy params' do
      call_api([:Test], :unnamespaced_input, { public: 'ok', secret: 'hidden' })

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response[:test][:has_params_method]).to be(false)
      expect(api_response[:test][:input_saw_secret]).to be(false)
    end

    it 'keeps path parameters out of unnamespaced body input' do
      call_api(:put, '/v1/tests/unnamespaced_input/route-id', { public: 'ok' })

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response[:test][:input_saw_test_id]).to be(false)
      expect(api_response[:test][:path_test_id]).to eq('route-id')
    end

    it 'exposes client values through input without changing path identity' do
      call_api(:put, '/v1/tests/unnamespaced_input/route-id', {
        public: 'ok',
        test_id: 'body-id'
      })

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response[:test][:input_saw_test_id]).to be(true)
      expect(api_response[:test][:input_test_id]).to eq('body-id')
      expect(api_response[:test][:path_test_id]).to eq('route-id')
    end

    it 'keeps route ids out of GET query input' do
      get '/v1/tests/query_input/route-id', { filter: 'visible' }, input: ''

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response[:test][:has_params_method]).to be(false)
      expect(api_response[:test][:input_saw_test_id]).to be(false)
      expect(api_response[:test][:filter]).to eq('visible')
      expect(api_response[:test][:path_test_id]).to eq('route-id')
    end

    it 'does not expose top-level JSON keys outside the input namespace' do
      call_api([:Test], :top_level_body, {
        secret: 'top-level hidden',
        test: {
          public: 'ok',
          secret: 'nested hidden'
        }
      })

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response[:test][:has_params_method]).to be(false)
      expect(api_response[:test][:input_saw_secret]).to be(false)
    end

    it 'keeps custom payload field names string-keyed by default' do
      call_api([:Test], :custom_payload, {
        test: {
          payload: {
            rawId: 'credential-id',
            response: {
              clientDataJSON: 'client-data'
            }
          }
        }
      })

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response[:test][:top_string_key]).to be(true)
      expect(api_response[:test][:top_symbol_key]).to be(false)
      expect(api_response[:test][:nested_string_key]).to be(true)
      expect(api_response[:test][:nested_symbol_key]).to be(false)
    end

    it 'symbolizes custom payload field names when requested' do
      call_api([:Test], :custom_payload_symbols, {
        test: {
          payload: {
            rawId: 'credential-id',
            response: {
              clientDataJSON: 'client-data'
            }
          }
        }
      })

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok
      expect(api_response[:test][:top_string_key]).to be(false)
      expect(api_response[:test][:top_symbol_key]).to be(true)
      expect(api_response[:test][:nested_string_key]).to be(false)
      expect(api_response[:test][:nested_symbol_key]).to be(true)
    end

    it 'denies OPTIONS for actions without an authorization block without raising' do
      call_api(:options, '/v1/tests/closed?method=POST')

      expect(last_response.status).to eq(403)
      expect(api_response).not_to be_ok
    end

    it 'rejects invalid route argument encoding in action descriptions' do
      call_api(:options, '/v1/tests/%FF?method=GET')

      expect(last_response.status).to eq(400)
      expect(api_response).not_to be_ok
      expect(api_response.message).to eq('invalid path parameter encoding')
    end

    it 'runs prepare, pre_exec, exec in order' do
      action_class(:order).calls.clear

      call_api([:Test], :order, {})

      expect(api_response).to be_ok
      expect(action_class(:order).calls).to eq(%i[prepare pre_exec exec])
    end

    it 'aborts execution when error! is called' do
      action_class(:abort).calls.clear

      call_api([:Test], :abort, {})

      expect(api_response).not_to be_ok
      expect(api_response.message).to eq('nope')
      expect(action_class(:abort).calls).to include(:exec)
      expect(action_class(:abort).calls).not_to include(:after_error)
    end

    it 'routes exec exceptions through hook' do
      with_exec_exception_hook do
        call_api([:Test], :boom, {})

        expect(last_response.status).to eq(422)
        expect(api_response).not_to be_ok
        expect(api_response.message).to eq('boom')
        expect(last_response.body).not_to match(/<html/i)
      end
    end

    it 'adds action_state_id to meta for blocking actions' do
      call_api([:Test], :block, {})

      expect(api_response).to be_ok
      meta = api_response.response[:_meta]
      expect(meta).to be_a(Hash)
      expect(meta).to have_key(:action_state_id)
    end
  end
end
