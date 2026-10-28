require_relative '../documentation/fixtures'
require_relative '../documentation/compilation'

RSpec.describe HaveAPI::TypeScriptClient::Documentation, '#render' do
  include TypeScriptDocumentationFixtures
  include TypeScriptDocumentationCompilation

  it 'strictly compiles actual public, protected, alias, nested, nullable, query and rejection snippets against the generated SDK' do
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
    snippets = %i[simple thorough].flat_map do |detail|
      contexts.map do |context|
        context.detail = detail
        result = adapter.render(kind: :example, context:)
        expect(result[:status]).to eq(:code)
        { status: :code, code: executable_documentation(adapter, context, result.fetch(:code)) }
      end
    end
    snippets << adapter.render(kind: :init, context: contexts.first)
    snippets << adapter.render(kind: :auth, context: contexts.first, auth_method: 'basic', auth_description: {})
    snippets << adapter.render(kind: :auth, context: contexts.first, auth_method: 'token', auth_description: schema['description']['authentication']['token'])
    expect(snippets.map { |item| item[:status] }).to all(eq(:code))
    Dir.mktmpdir('haveapi-typescript-documentation-') do |directory|
      stdout, stderr, status = compile_documentation(directory, schema, snippets.map { |item| item.fetch(:code) }, runtime_types:)
      expect(status.success?).to be(true), "Rendered documentation compilation failed:\n#{stdout}\n#{stderr}"
    end
  end
end
