module HaveAPI::Client
  # Represents action's state as returned from API resource ActionState.Show/Poll.
  class ActionState
    Progress = Struct.new(:current, :total, :unit) do
      def percent
        100.0 / total * current
      end

      def to_s
        "#{current}/#{total} #{unit}"
      end
    end

    attr_reader :progress

    def initialize(response)
      @data = response.response

      @progress = Progress.new(@data[:current], @data[:total], @data[:unit])
    end

    def label
      @data[:label]
    end

    def status
      @data[:status] === true
    end
    
    def finished?
      @data[:finished] === true
    end

    def can_cancel?
      @data[:can_cancel] === true
    end

    # Stop monitoring the action's state and attempt to cancel it. The `block`
    # is given to Action.wait_for_completion for the cancel operation. The block
    # is used only if the cancel operation is blocking.
    def cancel(&block)
      unless can_cancel?
        fail "action ##{@data[:id]} (#{label}) cannot be cancelled"
      end

      @cancel = true
      @cancel_block = block
    end

    def cancel?
      @cancel === true
    end

    def cancel_block
      @cancel_block
    end
    
    # Stop monitoring the action's state, the call from Action.wait_for_completion
    # will return.
    def stop
      @stop = true
    end

    def stop?
      !@stop.nil? && @stop
    end
  end
end
