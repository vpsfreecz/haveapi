module HaveAPI::CLI::Commands
  class ActionStateWait < HaveAPI::CLI::Command
    cmd :action_state, :wait
    args '<STATE ID>'
    desc 'Block until the action is finished'

    def exec(args)
      if args.size < 1
        warn "Provide argument STATE ID"
        exit(false)
      end

      @api.set_opts(block: false)

      state = HaveAPI::CLI::ActionState.new(
          @global_opts,
          @api,
          args.first.to_i
      )
      ret = state.wait_for_completion(timeout: @global_opts[:timeout])

      if ret.nil?
        warn "Timeout"
        exit(false)
      end
    end
  end
end
