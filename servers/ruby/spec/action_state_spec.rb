require 'time'

describe HaveAPI::Resources::ActionState do
  module ActionStateSpec
    FIXED_TIME = Time.utc(2020, 1, 1, 0, 0, 0)

    class State
      attr_reader :id, :label, :created_at, :updated_at, :status, :progress, :poll_calls

      def initialize(id:, label: 'job', status: true, finished: false, can_cancel: false,
                     progress: {}, valid: true, cancel_ret: true)
        @id = id
        @label = label
        @status = status
        @finished = finished
        @can_cancel = can_cancel
        @progress = progress
        @valid = valid
        @cancel_ret = cancel_ret
        @poll_calls = 0
        @created_at = FIXED_TIME
        @updated_at = FIXED_TIME
      end

      def valid?
        @valid
      end

      def finished?
        @finished
      end

      def can_cancel?
        @can_cancel
      end

      def poll(_input)
        @poll_calls += 1

        if @progress[:current]
          @progress = @progress.merge(current: @progress[:current] + 1)
        end

        @updated_at = Time.utc(2020, 1, 1, 0, 0, @poll_calls)
        self
      end

      def cancel
        @cancel_ret
      end
    end

    module Backend
      class << self
        attr_reader :states, :list_calls, :new_calls

        def reset!
          @states = {}
          @list_calls = []
          @new_calls = []
        end

        def add_state(state)
          @states[state.id] = state
        end

        def list_pending(user, from_id, limit, order)
          @list_calls << {
            user: user,
            from_id: from_id,
            limit: limit,
            order: order
          }
          @states.values
        end

        def new(user, id:)
          @new_calls << { user: user, id: id.to_i }
          @states[id.to_i] || State.new(id: id.to_i, valid: false)
        end
      end
    end
  end

  def get_action(path, params = nil)
    if params
      get path, params, input: ''
    else
      get path, {}, input: ''
    end
  end

  context 'without action_state backend' do
    empty_api
    use_version 1
    default_version 1

    it 'is not mounted without action_state backend' do
      header 'Accept', 'application/json'
      get_action '/v1/action_states'

      expect(last_response.status).to eq(404)
      expect(api_response).not_to be_ok
      expect(api_response.message).to eq('Action not found')
    end
  end

  context 'with action_state backend' do
    empty_api
    use_version 1
    default_version 1
    action_state ActionStateSpec::Backend

    before do
      ActionStateSpec::Backend.reset!
      header 'Accept', 'application/json'
    end

    it 'lists pending states and passes paging options' do
      ActionStateSpec::Backend.add_state(ActionStateSpec::State.new(id: 1))
      ActionStateSpec::Backend.add_state(ActionStateSpec::State.new(id: 2))

      get_action '/v1/action_states', action_state: { from_id: 10, limit: 2, order: 'oldest' }

      expect(last_response.status).to eq(200)
      expect(api_response).to be_ok

      states = api_response[:action_states]
      expect(states).to be_a(Array)
      expect(states.size).to eq(2)

      states.each do |state|
        expect(state.keys).to contain_exactly(
          :id, :label, :status, :finished, :current, :total, :unit,
          :can_cancel, :created_at, :updated_at
        )
        expect(state[:created_at]).to eq(ActionStateSpec::FIXED_TIME.iso8601)
        expect(state[:updated_at]).to eq(ActionStateSpec::FIXED_TIME.iso8601)
      end

      call = ActionStateSpec::Backend.list_calls.last
      expect(call[:user]).to be_nil
      expect(call[:from_id]).to eq(10)
      expect(call[:limit]).to eq(2)
      expect(call[:order]).to eq(:oldest)
    end

    it 'defaults order to newest' do
      ActionStateSpec::Backend.add_state(ActionStateSpec::State.new(id: 1))

      get_action '/v1/action_states'

      expect(ActionStateSpec::Backend.list_calls.last[:order]).to eq(:newest)
    end

    it 'shows state when valid' do
      ActionStateSpec::Backend.add_state(
        ActionStateSpec::State.new(id: 1, progress: {}, can_cancel: true)
      )

      get_action '/v1/action_states/1'

      expect(api_response).to be_ok
      state = api_response[:action_state]
      expect(state[:id]).to eq(1)
      expect(state[:current]).to eq(0)
      expect(state[:total]).to eq(0)
      expect(state[:unit]).to be_nil
      expect(state[:can_cancel]).to be(true)
    end

    it 'returns error when state invalid' do
      get_action '/v1/action_states/999'

      expect(api_response).not_to be_ok
      expect(api_response.message).to eq('action state not found')
    end

    it 'poll returns immediately if finished' do
      state = ActionStateSpec::State.new(
        id: 1,
        finished: true,
        progress: { current: 5, total: 10, unit: 'items' }
      )
      ActionStateSpec::Backend.add_state(state)

      get_action '/v1/action_states/1/poll', action_state: { timeout: 5 }

      expect(api_response).to be_ok
      ret = api_response[:action_state]
      expect(ret[:finished]).to be(true)
      expect(ret[:current]).to eq(5)
      expect(ret[:total]).to eq(10)
      expect(ret[:unit]).to eq('items')
      expect(state.poll_calls).to eq(0)
    end

    it 'poll returns immediately on timeout without polling' do
      state = ActionStateSpec::State.new(
        id: 1,
        finished: false,
        progress: { current: 0, total: 10 }
      )
      ActionStateSpec::Backend.add_state(state)

      get_action '/v1/action_states/1/poll', action_state: { timeout: 0 }

      expect(api_response).to be_ok
      expect(state.poll_calls).to eq(0)
    end

    it 'poll returns immediately when update_in check mismatches' do
      state = ActionStateSpec::State.new(
        id: 1,
        status: true,
        progress: { current: 1, total: 10 }
      )
      ActionStateSpec::Backend.add_state(state)

      get_action '/v1/action_states/1/poll', action_state: {
        timeout: 10,
        update_in: 5,
        status: false,
        current: 999,
        total: 10
      }

      expect(api_response).to be_ok
      ret = api_response[:action_state]
      expect(ret[:status]).to be(true)
      expect(ret[:current]).to eq(1)
      expect(ret[:total]).to eq(10)
      expect(state.poll_calls).to eq(0)
    end

    it 'poll uses state.poll when available' do
      state = ActionStateSpec::State.new(
        id: 1,
        finished: false,
        progress: { current: 0, total: 10 }
      )
      ActionStateSpec::Backend.add_state(state)

      get_action '/v1/action_states/1/poll', action_state: { timeout: 10 }

      expect(api_response).to be_ok
      ret = api_response[:action_state]
      expect(state.poll_calls).to eq(1)
      expect(ret[:current]).to eq(1)
    end

    it 'poll returns error when state invalid' do
      get_action '/v1/action_states/999/poll', action_state: { timeout: 0 }

      expect(api_response).not_to be_ok
      expect(api_response.message).to eq('action state not found')
    end

    it 'cancel returns ok for true' do
      ActionStateSpec::Backend.add_state(ActionStateSpec::State.new(id: 1, cancel_ret: true))

      call_api(:post, '/v1/action_states/1/cancel', {})

      expect(api_response).to be_ok
      expect(api_response.response[:_meta]).to be_a(Hash)
      expect(api_response.response[:_meta]).to have_key(:action_state_id)
      expect(api_response[:action_state]).to eq({})
    end

    it 'cancel returns action_state_id for numeric return' do
      ActionStateSpec::Backend.add_state(ActionStateSpec::State.new(id: 1, cancel_ret: 123))

      call_api(:post, '/v1/action_states/1/cancel', {})

      expect(api_response).to be_ok
      expect(api_response.response[:_meta][:action_state_id]).to eq(123)
    end

    it 'cancel returns error for false' do
      ActionStateSpec::Backend.add_state(ActionStateSpec::State.new(id: 1, cancel_ret: false))

      call_api(:post, '/v1/action_states/1/cancel', {})

      expect(api_response).not_to be_ok
      expect(api_response.message).to eq('cancellation failed')
    end

    it 'cancel returns error for NotImplementedError' do
      state = ActionStateSpec::State.new(id: 1)
      def state.cancel
        raise NotImplementedError, 'not supported'
      end
      ActionStateSpec::Backend.add_state(state)

      call_api(:post, '/v1/action_states/1/cancel', {})

      expect(api_response).not_to be_ok
      expect(api_response.message).to eq('not supported')
    end
  end
end
