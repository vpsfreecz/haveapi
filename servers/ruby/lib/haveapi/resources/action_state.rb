require 'haveapi/resource'

module HaveAPI::Resources
  class ActionState < HaveAPI::Resource
    desc 'Browse states of blocking actions'
    auth false
    version :all

    params(:all) do
      id :id
      string :label, label: 'Label'
      bool :finished, label: 'Finished'
      bool :status, label: 'Status',
                    desc: 'Determines whether the action is proceeding or failing'
      integer :current, label: 'Current progress'
      integer :total, label: 'Total',
                      desc: 'The action is finished when current equals to total'
      string :unit, label: 'Unit', desc: 'Unit of current and total'
      bool :can_cancel, label: 'Can cancel',
                        desc: 'When true, execution of this action can be cancelled'
      datetime :created_at, label: 'Created at'
      datetime :updated_at, label: 'Updated at',
                            desc: 'When was the progress last updated'
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

      desc 'Returns when the action is completed or timeout occurs'
      http_method :get
      route '{%{resource}_id}/poll'

      input(:hash) do
        float :timeout, label: 'Timeout', desc: 'in seconds', default: 15, fill: true
        float :update_in, label: 'Progress',
                          desc: 'number of seconds after which the state is returned if the progress ' \
                                'has changed',
                          nullable: true
        bool :status, desc: 'status to check with if update_in is set', nullable: true
        integer :current, desc: 'progress to check with if update_in is set', nullable: true
        integer :total, desc: 'progress to check with if update_in is set', nullable: true
      end

      output(:hash) do
        use :all
      end

      authorize { allow }

      def exec
        t = Time.now

        loop do
          state = @context.server.action_state.new(
            current_user,
            id: params[:action_state_id]
          )

          error!('action state not found') unless state.valid?

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
          id: params[:action_state_id]
        )

        return state_to_hash(state) if state.valid?

        error!('action state not found')
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
          id: params[:action_state_id]
        )

        error!('action state not found') unless state.valid?

        ret = state.cancel

        if ret.is_a?(::Numeric)
          @state_id = ret

        elsif ret
          ok!

        else
          error!('cancellation failed')
        end
      rescue RuntimeError, NotImplementedError => e
        error!(e.message)
      end

      attr_reader :state_id
    end
  end
end
