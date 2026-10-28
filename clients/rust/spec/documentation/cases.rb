module RustDocumentationCases
  module_function

  def cases
    [
      { name: 'scalars', resource: ['RustFixture'], action: 'Echo',
        sample: { request: { number: 0, flag: false, text: '' }, response: { received: {} }, status: true },
        assertion: 'assert_eq!(response.output.received, Some(serde_json::json!({"number": 0, "flag": false, "text": ""})));' },
      { name: 'null', resource: ['RustFixture'], action: 'Echo',
        sample: { request: { number: nil }, response: { received: {} }, status: true },
        assertion: 'assert_eq!(response.output.received, Some(serde_json::json!({"number": null})));' },
      { name: 'omitted', resource: ['RustFixture'], action: 'Echo',
        sample: { request: {}, response: { received: {} }, status: true },
        assertion: 'assert_eq!(response.output.received, Some(serde_json::json!({})));' },
      { name: 'custom', resource: ['RustFixture'], action: 'EchoCustom',
        sample: { request: { value: { 'text' => "quotes\"\\\n</script>ž", 'nested' => [0, false, nil] } },
                  response: { value: {} }, status: true },
        assertion: 'assert_eq!(response.output.value.as_ref().unwrap()["nested"], serde_json::json!([0, false, null]));' },
      { name: 'list', resource: ['RustFixture'], action: 'Batch',
        sample: { request: [{ number: 0 }, { number: 42 }], response: [{ number: 0 }], status: true },
        assertion: 'assert_eq!(response.output.iter().map(|item| item.number).collect::<Vec<_>>(), vec![Some(0), Some(42)]);' },
      { name: 'nested', resource: %w[Project Task], action: 'Show',
        sample: { path_params: [1, 1], response: { id: 1, done: false }, status: true },
        assertion: 'assert_eq!(response.output.id, Some(1)); assert_eq!(response.output.done, Some(false));' },
      { name: 'state', resource: %w[Project Task], action: 'Run',
        sample: { path_params: [1, 1], response: {}, status: true },
        assertion: 'assert!(response.meta.action_state_id.is_some());' },
      { name: 'failure', resource: ['Test'], action: 'Fail',
        sample: { status: false, http_status: 400 } },
      { name: 'index', resource: ['Project'], action: 'Index',
        sample: { response: [{ id: 1 }], status: true },
        assertion: 'assert!(!response.output.is_empty());' }
    ]
  end

  # Resolve canonical names from the retained fixture, never from Rust spelling.
  def context_for(context, entry)
    resources = context.description.fetch('resources')
    resource = nil
    path = entry.fetch(:resource).map do |component|
      name = resources.keys.find { |key| key.delete('_').casecmp?(component.delete('_')) }
      raise "Missing fixture resource #{component}" unless name

      resource = resources.fetch(name)
      resources = resource.fetch('resources')
      name
    end
    name = resource.fetch('actions').keys.find { |key| key.delete('_').casecmp?(entry.fetch(:action).delete('_')) }
    raise "Missing fixture action #{entry.fetch(:action)}" unless name

    context.with(resource_path: path, resource:, action_name: name,
                 action: resource.fetch('actions').fetch(name), sample: entry.fetch(:sample))
  end

  def assert_output(source, assertion)
    return source unless assertion

    raise 'Rendered main completion marker missing' unless source.include?('    Ok(())')

    source.sub('    Ok(())', "    #{assertion}\n    Ok(())")
  end

  def compose_authentication(auth_source, action_source)
    # The caller renders this fragment explicitly at Simple, never parses a main.
    compose_fragment(auth_source, action_source)
  end

  def compose_fragment(setup, fragment)
    raise 'Rendered initialization marker missing' unless setup.include?('    let _ = &api;')

    setup.sub('    let _ = &api;') { fragment }
  end
end
