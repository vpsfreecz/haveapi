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
            { id: params['test_id'] }
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
