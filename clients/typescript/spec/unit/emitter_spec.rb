require_relative '../spec_helper'
require_relative '../../lib/haveapi/typescript_client/emitter'
require_relative '../typescript/fixtures'
require 'open3'
require 'fileutils'

RSpec.describe HaveAPI::TypeScriptClient::Emitter do
  include TypeScriptEmitterFixtures

  def emitted_files
    described_class.new(emitter_ir, runtime_import: 'haveapi-client').files
  end

  it 'emits deterministic sorted UTF-8/LF sources without emission I/O or IR mutation' do
    ir = emitter_ir
    emitter = described_class.new(ir, runtime_import: 'haveapi-client')
    allow(File).to receive(:read).and_call_original
    first = emitter.files
    expect(first.keys).to eq(first.keys.sort)
    expect(first.keys).to include('api.ts', 'index.ts', 'runtime.ts', 'types.ts')
    expect(first.keys.count { |path| path.end_with?('/resource.ts') }).to eq(2)
    expect(first.keys.count { |path| path.include?('/actions/') }).to eq(ir[:actions].length)
    expect(emitter.files).to eq(first)
    expect(first.values).to all(be_a(String).and(have_attributes(encoding: Encoding::UTF_8)))
    expect(first.values).to all(end_with("\n"))
    expect(first.values).to all(satisfy { |content| !content.include?("\r") })
    expect(ir).to be_frozen
    expect(File).not_to have_received(:read)
  end

  it 'keeps original output keys, conservative fields, namespaces and one data narrowing' do
    files = emitted_files
    update = files.fetch('resources/widget/actions/update.ts')
    index = files.fetch('resources/widget/actions/index.ts')
    expect(update).to include('"wire-name"?: string | null;', '"wire_name"?: string | undefined;', '"name"?: string | null;')
    expect(index).to include('"inputNamespace":null', '"outputNamespace":"widgets"', '"metaNamespace":"_meta"')
    expect(update).to include('"custom"?: unknown;', '"owner"?: Partial<Record<"key" | "title", unknown>> | null;')
    expect(files['runtime.ts'].scan('response.data as T').length).to eq(1)
    expect(files['api.ts']).not_to include('new AsyncClient', 'fetch(', 'XMLHttpRequest')
  end

  it 'owns canonical actions and nested resources with explicit public types and acyclic static imports' do
    files = emitted_files
    expect(files).to have_key('resources/widget/resources/part/actions/show.ts')
    expect(files).not_to have_key('resources/widget/actions/change.ts')
    expect(files.fetch('api.ts')).not_to include('descriptor', 'export interface', 'export type Widget', 'executeAction')
    expect(files.fetch('resources/widget/resource.ts')).to include('"change": action', '"update": action')
    expect(files.fetch('types.ts').lines.grep(/^export /)).to all(start_with('export type {'))
    expect(files.fetch('types.ts')).not_to include('createAction', 'createResource', 'descriptor')
    visited = {}
    visit = lambda do |path, ancestors|
      expect(ancestors).not_to include(path)
      return if visited[path]

      files.fetch(path).scan(/^import \{.*?from "([^"]+)";/).flatten.each do |specifier|
        expect(specifier).to end_with('.js')
        target = File.expand_path(specifier, File.dirname("/#{path}")).delete_prefix('/').sub(/\.js\z/, '.ts')
        visit.call(target, ancestors + [path])
      end
      visited[path] = true
    end
    visit.call('api.ts', [])
    expect(visited.keys).to include('runtime.ts', 'resources/widget/resource.ts', 'resources/widget/resources/part/actions/show.ts')
    expect(files.values.join.scan('const descriptor =').length).to eq(emitter_ir[:actions].length)
  end

  it 'rejects case-folded resource and action paths with both original schema paths' do
    schema = emitter_schema
    schema['description']['resources']['WiDget'] = { 'resources' => {}, 'actions' => {} }
    expect { described_class.new(HaveAPI::TypeScriptClient::IR.build(schema), runtime_import: 'haveapi-client').files }
      .to raise_error(HaveAPI::TypeScriptClient::Error, /path collision.*WiDget.*widget/)
    schema = emitter_schema
    schema['description']['resources']['widget']['actions']['iNdex'] = action(path: '/api/v1.0/widgets/mixed', method: 'GET')
    expect { described_class.new(HaveAPI::TypeScriptClient::IR.build(schema), runtime_import: 'haveapi-client').files }
      .to raise_error(HaveAPI::TypeScriptClient::Error, %r{path collision.*widget/iNdex.*widget/index})
  end

  it 'refuses unsafe planned paths and file/directory conflicts before rendering' do
    emitter = described_class.new(emitter_ir, runtime_import: 'haveapi-client')
    unsafe = { path: 'resources/../escape.ts', template: 'resource', origin: 'wire/unsafe' }
    allow(emitter).to receive(:file_plan).and_return([unsafe])
    expect { emitter.files }.to raise_error(HaveAPI::TypeScriptClient::Error, %r{unsafe generated path.*wire/unsafe})
    conflict = [
      { path: 'resources/item.ts', origin: 'wire/file' },
      { path: 'resources/item.ts/child.ts', origin: 'wire/directory' }
    ]
    allow(emitter).to receive(:file_plan).and_return(conflict)
    expect { emitter.files }.to raise_error(HaveAPI::TypeScriptClient::Error, %r{path collision.*wire/file.*wire/directory})
  end

  it 'detects an object metadata field collision instead of overwriting it' do
    schema = emitter_schema
    fixture_action(schema)['input']['parameters']['_meta'] = parameter
    expect { described_class.new(HaveAPI::TypeScriptClient::IR.build(schema), runtime_import: 'haveapi-client').files }
      .to raise_error(HaveAPI::TypeScriptClient::Error, /metadata.*collid/)
  end

  it 'strictly compiles positive and negative consumers and preserves the executor contract' do
    root = File.expand_path('../../../..', __dir__)
    node = ENV.fetch('NODE', 'node')
    compiler = ENV.fetch('TSC', File.join(root, 'clients/js/node_modules/typescript/bin/tsc'))
    runtime_types = ENV.fetch('HAVEAPI_TYPESCRIPT_RUNTIME_TYPES', File.join(root, 'clients/js/dist/types/haveapi.d.ts'))
    consumer = File.expand_path('../typescript/consumer.ts', __dir__)
    spy = File.expand_path('../typescript/runtime_spy.mjs', __dir__)
    Dir.mktmpdir('haveapi-typescript-emitter-') do |directory|
      generated = File.join(directory, 'generated')
      FileUtils.mkdir_p(generated)
      emitted_files.each do |path, content|
        target = File.join(generated, path)
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, content)
      end
      FileUtils.cp(consumer, File.join(directory, 'consumer.ts'))
      File.write(File.join(directory, 'package.json'), JSON.generate(type: 'module'))
      config = {
        compilerOptions: {
          target: 'ES2022', module: 'NodeNext', moduleResolution: 'NodeNext',
          strict: true, exactOptionalPropertyTypes: true, noUncheckedIndexedAccess: true, verbatimModuleSyntax: true, skipLibCheck: false,
          types: [], lib: %w[ES2022 DOM], outDir: './compiled',
          paths: { 'haveapi-client' => [runtime_types] }
        },
        include: ['consumer.ts', 'generated/**/*.ts']
      }
      File.write(File.join(directory, 'tsconfig.json'), JSON.generate(config))
      stdout, stderr, status = Open3.capture3(node, compiler, '-p', File.join(directory, 'tsconfig.json'))
      expect(status.success?).to be(true), "TypeScript consumer failed:\n#{stdout}\n#{stderr}"
      stdout, stderr, status = Open3.capture3(node, spy, File.join(directory, 'compiled/generated/index.js'))
      expect(status.success?).to be(true), "Executor spy failed:\n#{stdout}\n#{stderr}"
      expect(stdout).to include('runtime spy contract passed')
    end
  end
end
