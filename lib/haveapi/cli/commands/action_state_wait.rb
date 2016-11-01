module HaveAPI::CLI::Commands
  class ActionStateWait < HaveAPI::CLI::Command
    cmd :action_state, :wait
    args '<STATE ID>'
    desc 'Block until the action is finished'

    include HaveAPI::CLI::ActionState

    def exec(args)
      if args.size < 1
        warn "Provide argument STATE ID"
        exit(false)
      end

      ret = wait_for_completion(
          @global_opts[:version],
          @api.action_state.actions[:poll],
          args.first.to_i,
          timeout: @global_opts[:timeout],
      )

      if ret.nil?
        warn "Timeout"
        exit(false)
      end
    end
  end
end
