require_relative '../../lib/haveapi/typescript_client/emitter'
require 'fileutils'
require 'open3'

module TypeScriptDocumentationCompilation
  # Wrap the exact action fragment with the separately rendered setup.
  def executable_documentation(adapter, context, source)
    return source unless context.detail == :simple

    provider = context.action['auth'] == false ? nil : %w[basic token].find { |name| context.description['authentication'].has_key?(name) }
    setup = adapter.render(kind: provider ? :auth : :init, context:, auth_method: provider).fetch(:code)
    raise 'Rendered initialization marker missing' unless setup.include?('  void api;')

    imports, body = source.lines.partition { |line| line.start_with?('import ') }
    imports.join + setup.sub('  void api;') { body.join.rstrip }
  end

  def compile_documentation(directory, schema, snippets, runtime_types:, emit: false)
    root = File.expand_path('../../../..', __dir__)
    node = ENV.fetch('NODE', 'node')
    compiler = ENV.fetch('TSC', File.join(root, 'clients/js/node_modules/typescript/bin/tsc'))
    emitted = HaveAPI::TypeScriptClient::Emitter.new(HaveAPI::TypeScriptClient::IR.build(schema), runtime_import: 'haveapi-client').files
    emitted.each do |path, content|
      target = File.join(directory, 'generated', path)
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, content)
    end
    snippets.each_with_index { |code, index| File.write(File.join(directory, "sample#{index}.ts"), code) }
    File.write(File.join(directory, 'package.json'), JSON.generate(type: 'module'))
    config = {
      compilerOptions: {
        target: 'ES2022', module: 'NodeNext', moduleResolution: 'NodeNext', strict: true,
        exactOptionalPropertyTypes: true, noUncheckedIndexedAccess: true, verbatimModuleSyntax: true,
        types: ['node'], typeRoots: [File.join(root, 'clients/js/node_modules/@types')], lib: %w[ES2022 DOM],
        noEmit: !emit, outDir: './compiled',
        paths: { 'widget-client' => [File.join(directory, 'generated/index.ts')], 'haveapi-client' => [runtime_types] }
      }, include: ['**/*.ts']
    }
    File.write(File.join(directory, 'tsconfig.json'), JSON.generate(config))
    Open3.capture3(node, compiler, '-p', File.join(directory, 'tsconfig.json'))
  end
end
