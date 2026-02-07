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