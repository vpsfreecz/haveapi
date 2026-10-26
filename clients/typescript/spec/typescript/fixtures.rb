module TypeScriptEmitterFixtures
  include TypeScriptFixtures

  def emitter_schema
    schema = snapshot
    actions = schema['description']['resources']['widget']['actions']
    fields = {
      'name' => parameter('String', required: true),
      'enabled' => parameter('Boolean'), 'count' => parameter('Integer'),
      'ratio' => parameter('Float'), 'cleared' => parameter('Text', nullable: true),
      'custom' => parameter('Custom'), 'optional' => parameter,
      'published_at' => parameter('Datetime'),
      'owner' => parameter('Resource').merge('resource' => ['widget'], 'value_id' => 'key', 'value_label' => 'title'),
      'wire-name' => parameter
    }
    actions['update']['input'] = io(fields)
    actions['update']['output'] = io(fields)
    actions['update']['aliases'] = ['change']
    actions['update']['meta'] = {
      'global' => { 'input' => io('notify' => parameter('Boolean')), 'output' => io('count' => parameter('Integer')) },
      'object' => { 'input' => io('revision' => parameter('Integer')), 'output' => io('revision' => parameter('Integer')) }
    }
    actions['index'] = action(path: '/api/v1.0/widgets', method: 'GET').merge(
      'input' => io({ 'limit' => parameter('Integer'), 'custom' => parameter('Custom', nullable: true) }, namespace: false),
      'output' => io(fields, namespace: 'widgets', layout: 'object_list'),
      'meta' => actions['update']['meta'].merge('object' => { 'output' => io('revision' => parameter('Integer')) })
    )
    actions['empty'] = action(path: '/api/v1.0/widgets/empty', method: 'POST').merge('input' => nil, 'output' => nil)
    actions['audit'] = action(path: '/api/v1.0/widgets/audit', method: 'POST').merge(
      'input' => nil,
      'meta' => { 'global' => { 'input' => io('token' => parameter(required: true)) } }
    )
    actions['object_only'] = action(path: '/api/v1.0/widgets/object-only', method: 'POST').merge(
      'input' => nil, 'output' => nil,
      'meta' => { 'object' => { 'input' => io('revision' => parameter('Integer', required: true)) } }
    )
    actions['hashes'] = action(path: '/api/v1.0/widgets/hashes', method: 'GET').merge(
      'input' => nil, 'output' => io(fields, namespace: 'hashes', layout: 'hash_list')
    )
    schema['description']['resources']['widget']['resources']['part'] = {
      'resources' => {}, 'actions' => {
        'show' => action(path: '/api/v1.0/widgets/{widget_id}/parts/{part-id}', method: 'GET').merge('input' => nil)
      }
    }
    schema
  end

  def emitter_ir
    HaveAPI::TypeScriptClient::IR.build(emitter_schema)
  end
end
