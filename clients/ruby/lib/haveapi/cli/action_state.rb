require 'ruby-progressbar'

module HaveAPI::CLI
  # This class can watch action's state and show it's progress with a progress bar.
  #
  # When interrupted, the user is asked whether he wishes to cancel the action,
  # then it shows the progress of cancellation.
  #
  # Methods from this class may invoke `exit()` whenever appropriate.
  class ActionState
    # @param opts [Hash]
    # @param action [HaveAPI::Client::Action]
    # @param id [Integer]
    def initialize(opts, client, id)
      @opts = opts
      @client = client
      @id = id
    end

    # Block until the action is finished or timeout is reached. Progress is shown with
    # a progress bar. Offers cancellation on interrupt.
    #
    # @param timeout [Float]
    # @param cancel [Boolean] determines whether we're waiting for a cancel to finish
    def wait_for_completion(id: nil, timeout: nil, cancel: false)
      id ||= @id

      if cancel
        puts 'Waiting for the action to cancel (hit Ctrl+C to skip)...'
      else
        puts 'Waiting for the action to complete (hit Ctrl+C to skip)...'
      end

      last_status = false
      can_cancel = false

      begin
        ret = HaveAPI::Client::Action.wait_for_completion(
          @client,
          id,
          timeout:
        ) do |state|
          last_status = state.status
          can_cancel = state.can_cancel?

          update_progress(state, cancel)
        end
      rescue Interrupt
        @pb && @pb.stop
        puts

        cancel_action(timeout:) if can_cancel && !cancel && last_status

        puts
        print_help(id)
        exit(false)
      end

      if ret
        @pb && @pb.finish
      else
        @pb && @pb.stop
      end

      ret
    end

    # Ask the user if he wishes to cancel the action. If so, execute cancel
    # and call self.wait_for_completion on the cancellation, if it is blocking
    # operation.
    def cancel_action(timeout: nil)
      $stdout.write('Do you wish to cancel the action? [y/N]: ')
      $stdout.flush

      return unless $stdin.readline.strip.downcase == 'y'

      begin
        res = HaveAPI::Client::Action.cancel(@client, @id)
      rescue HaveAPI::Client::ActionFailed => e
        res = e.response
      end

      if res.is_a?(HaveAPI::Client::Response) && res.ok?
        puts 'Cancelled'
        exit

      elsif res
        @pb.resume

        wait_for_completion(
          id: res,
          timeout:,
          cancel: true
        )
        exit
      end

      warn "Cancel failed: #{res.message}"
      exit(false)
    end

    def print_help(id = nil)
      id ||= @id

      puts 'Run'
      puts "  #{$0} action_state show #{id}"
      puts 'or'
      puts "  #{$0} action_state wait #{id}"
      puts "to check the action's progress."
    end

    protected

    def update_progress(state, cancel)
      @pb ||= ProgressBar.create(
        title: cancel ? 'Cancelling' : 'Executing',
        total: state.progress.total,
        format: if state.progress.total && state.progress.total > 0
                  "%t: [%B] %c/%C #{state.progress.unit}"
                else
                  '%t: [%B]'
                end,
        starting_at: state.progress.current,
        autofinish: false
      )

      @pb.title = if state.status
                    cancel ? 'Cancelling' : 'Executing'

                  else
                    'Failing'
                  end

      if state.progress.total && state.progress.total > 0
        @pb.progress = state.progress.current
        @pb.total = state.progress.total
        @pb.format("%t: [%B] %c/%C #{state.progress.unit}")

      else
        @pb.total = nil
        @pb.format("%t: [%B] #{state.progress.unit}")
        @pb.increment
      end
    end
  end
end
