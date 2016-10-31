module HaveAPI::Resources
  class ActionState < HaveAPI::Resource
    auth false
    version :all

    params(:all) do
      id :id
      string :label
      bool :finished
      bool :status
      integer :current
      integer :total
      string :unit
    end

    module Mixin
      def state_to_hash(state)
        hash = {
            id: state.id,
            label: state.label,
            status: state.status,
        }

        if state.finished?
          hash[:finished] = true

        else
          hash[:finished] = false
        end
          
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

      output(:hash_list) do
        use :all
      end

      authorize { allow }

      def exec
        ret = []
        actions = @context.server.action_state.list_pending(
            current_user,
            input[:offset],
            input[:limit]
        )

        actions.each do |state|
          ret << state_to_hash(state)
        end

        ret
      end
    end
    
    class Poll < HaveAPI::Action
      include Mixin

      desc 'Returns when the action is completed or timeout occurs'
      http_method :get
      route ':%{resource}_id'

      input(:hash) do
        float :timeout, label: 'Timeout', desc: 'in seconds', default: 15, fill: true
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

          error('action state not found') unless state.valid?

          return state_to_hash(state) if state.finished? || (Time.now - t) >= input[:timeout]
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
        
        error('action state not found')
      end
    end

    class Cancel < HaveAPI::Action
      http_method :post
      route ':%{resource}_id'
      
      authorize { allow }

      def exec
        @context.server.action_state.cancel(
            current_user,
            params[:action_state_id]
        )

      rescue NotImplementedError => e
        error(e.message)
      end
    end
  end
end
