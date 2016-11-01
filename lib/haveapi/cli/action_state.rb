require 'ruby-progressbar'

module HaveAPI::CLI
  module ActionState
    # @param version [String]
    # @param action [HaveAPI::Client::Action]
    # @param id [Integer]
    def wait_for_completion(version, action, id, timeout: nil)
      puts "Waiting for the action to complete (hit Ctrl+C to skip)..."
      
      pb = ProgressBar.create(
          title: 'Executing',
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
          pb.title = state[:status] ? 'Executing' : 'Failing'

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

        if last_status
          STDOUT.write("Do you wish to cancel the action? [y/N]: ")
          STDOUT.flush

          if STDIN.readline.strip.downcase == 'y'
            begin
              res = action.cancel(
                  id,
                  desc: description && description[:resources][:action_state]
              )

            rescue HaveAPI::Client::ActionFailed => e
              res = e.response

            ensure
              if res.ok?
                puts "Cancelled"
                exit
              end

              warn "Cancel failed: #{res.message}"
              exit(false)
            end
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
