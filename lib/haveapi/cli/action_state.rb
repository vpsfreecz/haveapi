require 'ruby-progressbar'

module HaveAPI::CLI
  module ActionState
    # @param version [String]
    # @param action [HaveAPI::Client::Action]
    # @param id [Integer]
    # @param timeout [Float]
    # @param cancel [Boolean] determines whether we're waiting for a cancel to finish
    def wait_for_completion(version, action, id, timeout: nil, cancel: false)
      if cancel
        puts "Waiting for the action to cancel (hit Ctrl+C to skip)..."
      else
        puts "Waiting for the action to complete (hit Ctrl+C to skip)..."
      end
      
      pb = ProgressBar.create(
          title: cancel ? 'Cancelling' : 'Executing',
          total: nil,
          format: '%t: [%B]',
          starting_at: 0,
          autofinish: false,
      )
      last_status = false
    
      description = action.api.describe_api(version) unless action.client

      begin
        ret = action.wait_for_completion(
            id,
            desc: description && description[:resources][:action_state],
            timeout: timeout,
        ) do |state|
          last_status = state[:status]

          if state[:status]
            pb.title = cancel ? 'Cancelling' : 'Executing'

          else
            pb.title = 'Failing'
          end

          if state[:total] && state[:total] > 0
            pb.progress = state[:current]
            pb.total = state[:total]
            pb.format("%t: [%B] %c/%C #{state[:unit]}")

          else
            pb.total = nil
            pb.format("%t: [%B] #{state[:unit]}")
            pb.increment
          end
        end

      rescue Interrupt
        pb.stop
        puts

        if !cancel && last_status
          STDOUT.write("Do you wish to cancel the action? [y/N]: ")
          STDOUT.flush

          if STDIN.readline.strip.downcase == 'y'
            begin
              action.reset
              res = action.cancel(
                  id,
                  desc: description && description[:resources][:action_state]
              )

            rescue HaveAPI::Client::ActionFailed => e
              res = e.response
            end
        
            if res.is_a?(HaveAPI::Client::Response) && res.ok?
              puts "Cancelled"
              exit

            elsif res
              wait_for_completion(
                  version,
                  action,
                  res,
                  timeout: timeout,
                  cancel: true,
              )
              exit
            end

            warn "Cancel failed: #{res.message}"
            exit(false)
          end
        end

        puts
        action_state_help(id)
        exit(false)
      end

      if ret
        pb.finish
      else
        pb.stop
      end

      ret
    end

    def action_state_help(id)
      puts "Run"
      puts "  #{$0} action_state show #{id}"
      puts "or"
      puts "  #{$0} action_state wait #{id}"
      puts "to check the action's progress."
    end
  end
end
