module HaveAPI::CLI::Commands
  class ActionStateWait < HaveAPI::CLI::Command
    cmd :action_state, :wait
    args '<STATE ID>'
    desc 'Block until the action is finished'

    include HaveAPI::CLI::ActionState
    
    def options(opts)
      @opts = {}

      opts.on(
          '--timeout SEC',
          Float,
          'Fail when the action does not finish within the timeout'
      ) do |v|
        @opts[:timeout] = v.to_f
      end
    end

    def exec(args)
      if args.size < 1
        warn "Provide argument STATE ID"
        exit(false)
      end

      ret = wait_for_completion(
          @global_opts[:version],
          @api.action_state.actions[:poll],
          args.first.to_i,
          timeout: @opts[:timeout],
      )

      if ret.nil?
        warn "Timeout"
        exit(false)
      end
    end
  end
end
