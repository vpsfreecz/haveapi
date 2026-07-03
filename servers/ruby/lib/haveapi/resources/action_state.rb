require 'haveapi/resource'

module HaveAPI::Resources
  class ActionState < HaveAPI::Resource
    desc 'Browse states of blocking actions'
    auth false
    version :all

    params(:all) do
      id :id
      string :label, label: HaveAPI.message('haveapi.parameters.action_state.label.label')
      bool :finished, label: HaveAPI.message('haveapi.parameters.action_state.finished.label')
      bool :status,
           label: HaveAPI.message('haveapi.parameters.action_state.status.label'),
           desc: HaveAPI.message('haveapi.parameters.action_state.status.description')
      integer :current, label: HaveAPI.message('haveapi.parameters.action_state.current.label')
      integer :total,
              label: HaveAPI.message('haveapi.parameters.action_state.total.label'),
              desc: HaveAPI.message('haveapi.parameters.action_state.total.description')
      string :unit,
             label: HaveAPI.message('haveapi.parameters.action_state.unit.label'),
             desc: HaveAPI.message('haveapi.parameters.action_state.unit.description')
      bool :can_cancel,
           label: HaveAPI.message('haveapi.parameters.action_state.can_cancel.label'),
           desc: HaveAPI.message('haveapi.parameters.action_state.can_cancel.description')
      datetime :created_at, label: HaveAPI.message('haveapi.parameters.action_state.created_at.label')
      datetime :updated_at,
               label: HaveAPI.message('haveapi.parameters.action_state.updated_at.label'),
               desc: HaveAPI.message('haveapi.parameters.action_state.updated_at.description')
    end

    module Mixin
      def state_to_hash(state)
        hash = {
          id: state.id,
          label: state.label,
          status: state.status,
          created_at: state.created_at,
          updated_at: state.updated_at,
          can_cancel: state.can_cancel?
        }

        hash[:finished] = state.finished?

        progress = state.progress
        hash[:current] = progress[:current] || 0
        hash[:total] = progress[:total] || 0
        hash[:unit] = progress[:unit]

        hash
      end
    end

    class Index < HaveAPI::Actions::Default::Index
      include Mixin

      desc 'List states of pending actions'

      input(:hash) do
        string :order, choices: %w[newest oldest], default: 'newest', fill: true
      end

      output(:hash_list) do
        use :all
      end

      authorize { allow }

      def exec
        actions = @context.server.action_state.list_pending(
          current_user,
          input[:from_id],
          input[:limit],
          input[:order].to_sym
        )

        actions.map do |state|
          state_to_hash(state)
        end
      end
    end

    class Poll < HaveAPI::Action
      include Mixin

      MAX_TIMEOUT = 30

      desc 'Returns when the action is completed or timeout occurs'
      http_method :get
      route '{%{resource}_id}/poll'

      input(:hash) do
        float :timeout,
              label: HaveAPI.message('haveapi.parameters.action_state.poll.timeout.label'),
              desc: HaveAPI.message('haveapi.parameters.action_state.poll.timeout.description'),
              default: 15,
              fill: true,
              number: { min: 0, max: MAX_TIMEOUT }
        float :update_in,
              label: HaveAPI.message('haveapi.parameters.action_state.poll.update_in.label'),
              desc: HaveAPI.message('haveapi.parameters.action_state.poll.update_in.description'),
              nullable: true
        bool :status,
             desc: HaveAPI.message('haveapi.parameters.action_state.poll.status.description'),
             nullable: true
        integer :current,
                desc: HaveAPI.message('haveapi.parameters.action_state.poll.current.description'),
                nullable: true
        integer :total,
                desc: HaveAPI.message('haveapi.parameters.action_state.poll.total.description'),
                nullable: true
      end

      output(:hash) do
        use :all
      end

      authorize { allow }

      def exec
        if input[:timeout] > MAX_TIMEOUT
          error!(
            HaveAPI.message('haveapi.action_state.timeout_max', max: MAX_TIMEOUT),
            {},
            http_status: 400
          )
        end

        t = Time.now

        loop do
          state = @context.server.action_state.new(
            current_user,
            id: path_params['action_state_id']
          )

          error!(HaveAPI.message('haveapi.action_state.not_found')) unless state.valid?

          if state.finished? || (Time.now - t) >= input[:timeout]
            return state_to_hash(state)

          elsif input[:update_in]
            new_state = state_to_hash(state)

            %i[status current total].each do |v|
              return new_state if input[v] != new_state[v]
            end
          end

          return state_to_hash(state.poll(input)) if state.respond_to?(:poll)

          sleep(1)
        end
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      include Mixin

      desc 'Show state of a pending action'

      output(:hash) do
        use :all
      end

      authorize { allow }

      def exec
        state = @context.server.action_state.new(
          current_user,
          id: path_params['action_state_id']
        )

        return state_to_hash(state) if state.valid?

        error!(HaveAPI.message('haveapi.action_state.not_found'))
      end
    end

    class Cancel < HaveAPI::Action
      http_method :post
      route '{%{resource}_id}/cancel'
      blocking true

      output(:hash) {}

      authorize { allow }

      def exec
        state = @context.server.action_state.new(
          current_user,
          id: path_params['action_state_id']
        )

        error!(HaveAPI.message('haveapi.action_state.not_found')) unless state.valid?

        ret = state.cancel

        if ret.is_a?(::Numeric)
          @state_id = ret

        elsif ret
          ok!

        else
          error!(HaveAPI.message('haveapi.action_state.cancellation_failed'))
        end
      rescue RuntimeError, NotImplementedError => e
        error!(e.message)
      end

      attr_reader :state_id
    end
  end
end
