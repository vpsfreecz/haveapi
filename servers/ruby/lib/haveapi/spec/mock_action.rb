module HaveAPI::Spec
  class MockAction
    def initialize(test, server, action, path, v)
      @test = test
      @server = server
      @action = action
      @path = path
      @v = v
    end

    def call(input, user: nil, &block)
      action = @action.new(nil, @v, input, nil, HaveAPI::Context.new(
        @server,
        version: @v,
        action: @action,
        path: @path,
        params: input,
        user: user,
        endpoint: true
      ))

      unless action.authorized?(user)
        fail 'Access denied. Insufficient permissions.'
      end

      status, data, errors = action.safe_exec
      fail (data || 'action failed') unless status
      action.instance_exec(@test, &block)
      data
    end
  end
end
