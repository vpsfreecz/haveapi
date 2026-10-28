require_relative '../documentation/fixtures'
require_relative '../documentation/compilation'

RSpec.describe HaveAPI::TypeScriptClient::Documentation, '#render' do
  include TypeScriptDocumentationFixtures
  include TypeScriptDocumentationCompilation

  it 'strictly compiles actual public, protected, alias, nested, nullable, query and rejection snippets against the generated API client' do
    root = File.expand_path('../../../..', __dir__)
    runtime_types = ENV.fetch('HAVEAPI_TYPESCRIPT_RUNTIME_TYPES', File.join(root, 'clients/js/dist/types/haveapi.d.ts'))
    schema = documentation_snapshot
    adapter = documentation_adapter(schema)
    contexts = [documentation_context(schema), documentation_context(schema, action_name: 'index'),
                documentation_context(schema, action_name: 'show', resource_path: %w[widget part])]
    rejected = documentation_context(schema)
    rejected.sample[:status] = false
    contexts << rejected
    alias_context = documentation_context(schema)
    alias_context.action_name = 'change'
    contexts << alias_context
    # Output names stay wire names even though resource/action names normalize.
    special_fields = { 'with space' => parameter, 'quote"\\<&' => parameter, '7days' => parameter, '雪' => parameter }
    %w[update index].each { |name| schema['description']['resources']['widget']['actions'][name]['output']['parameters'].merge!(special_fields) }
    %w[update index].each do |action_name|
      context = documentation_context(schema, action_name:)
      output = special_fields.to_h { |name, _| [name, 'visible value'] }.merge('wire-name' => 'mapped')
      context.sample[:response] = action_name == 'index' ? [output] : output
      contexts << context
    end
    resource = schema['description']['resources']
    resource['my-widget'] = Marshal.load(Marshal.dump(resource['widget']))
    actions = resource['my-widget']['actions']
    actions['do-work'] = actions.delete('update')
    normalized = documentation_context(schema)
    normalized.resource_path = ['my-widget']
    normalized.action_name = 'change'
    normalized.action = actions['do-work']
    contexts << normalized
    adapter = documentation_adapter(schema)
    snippets = %i[simple thorough].flat_map do |detail|
      contexts.map do |context|
        context.detail = detail
        result = adapter.render(kind: :example, context:)
        expect(result[:status]).to eq(:code)
        { status: :code, code: executable_documentation(adapter, context, result.fetch(:code)) }
      end
    end
    snippets << adapter.render(kind: :init, context: contexts.first)
    %i[simple thorough].each do |detail|
      context = documentation_context(schema, detail:)
      snippets << adapter.render(kind: :auth, context:, auth_method: 'basic', auth_description: {})
      snippets << adapter.render(kind: :auth, context:, auth_method: 'token', auth_description: schema['description']['authentication']['token'])
    end
    expect(snippets.map { |item| item[:status] }).to all(eq(:code))
    Dir.mktmpdir('haveapi-typescript-documentation-') do |directory|
      stdout, stderr, status = compile_documentation(directory, schema, snippets.map { |item| item.fetch(:code) }, runtime_types:)
      expect(status.success?).to be(true), "Rendered documentation compilation failed:\n#{stdout}\n#{stderr}"
    end
  end
end
