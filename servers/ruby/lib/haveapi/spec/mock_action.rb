module HaveAPI::Spec
  class MockAction
    def initialize(test, server, action, url, v)
      @test = test
      @server = server
      @action = action
      @url = url
      @v = v
    end

    def call(input, user: nil, &block)
      action = @action.new(nil, @v, input, nil, HaveAPI::Context.new(
          @server,
          version: @v,
          action: @action,
          url: @url,
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
