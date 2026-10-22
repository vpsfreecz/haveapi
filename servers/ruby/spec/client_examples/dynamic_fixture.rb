module DynamicExampleFixture
  def dynamic_action
    {
      method: 'POST', path: '/mount/v2/parents/{parent_id}/widgets/{widget_id}',
      input: { layout: :hash, namespace: :widget,
               parameters: { name: { type: 'String' }, enabled: { type: 'Boolean' }, count: { type: 'Integer' },
                             nullable: { type: 'String', nullable: true }, metadata: { type: 'Custom' } } },
      output: { layout: :hash, namespace: :widget, parameters: { id: { type: 'Integer' } } }
    }
  end

  def dynamic_sample
    {
      path_params: [7, 'name/with space'],
      request: { name: "Unicode žluťoučký \"quote\"\\\n</script>", enabled: false, count: 0,
                 nullable: nil, metadata: { '__proto__' => { 'constructor' => [false, 0, nil, ''] } } },
      response: { id: 0 }, status: true
    }
  end

  def dynamic_context(**changes)
    HaveAPI::ClientExample::Context.new(
      version: '2', host: 'api.example.test', base_url: 'https://api.example.test/mount/',
      version_url: 'https://api.example.test/mount/v2/',
      description: { authentication: { basic: {}, token: {}, oauth2: {} }, resources: {} },
      resource_path: %w[constructor resources], resource: {}, action_name: "new\"\n</script>",
      action: dynamic_action, sample: dynamic_sample, **changes
    )
  end

  def token_description
    { resources: { token: { actions: { 'request' => { input: { parameters: {
      'login-name' => { type: 'String' }, password: { type: 'String' }, lifetime: { type: 'String' }
    } } } } } } }
  end
end
