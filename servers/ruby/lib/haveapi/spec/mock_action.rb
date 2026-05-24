module HaveAPI::Spec
  class MockAction
    def initialize(test, server, action, path, v)
      @test = test
      @server = server
      @action = action
      @path = path
      @v = v
    end

    def call(input, user: nil, &)
      context = HaveAPI::Context.new(
        @server,
        version: @v,
        action: @action,
        path: @path,
        input:,
        user:,
        endpoint: true
      )
      action = @action.new(nil, @v, {}, input, context)

      unless action.authorized?(user)
        raise 'Access denied. Insufficient permissions.'
      end

      status, data, errors = action.safe_exec
      raise(data || 'action failed') unless status

      action.instance_exec(@test, &)
      data
    end
  end
end
