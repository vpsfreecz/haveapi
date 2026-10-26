# Run after independent review, with a prepared exact npm 0.30.2 installation:
# HAVEAPI_TYPESCRIPT_RUNTIME=/absolute/path/to/haveapi-client/dist/haveapi-client.js
# nix develop --command bundle exec ruby clients/typescript/spec/typescript/wire.rb
require 'rspec/core'
require_relative '../spec_helper'
require_relative '../../lib/haveapi/typescript_client/emitter'
require_relative 'fixtures'
require 'fileutils'
require 'open3'

include TypeScriptEmitterFixtures

root = File.expand_path('../../../..', __dir__)
node = ENV.fetch('NODE', 'node')
compiler = ENV.fetch('TSC', File.join(root, 'clients/js/node_modules/typescript/bin/tsc'))
runtime = File.expand_path(ENV.fetch('HAVEAPI_TYPESCRIPT_RUNTIME'))
runtime_types = File.join(File.dirname(runtime), 'types/haveapi.d.ts')
raise 'Prepared published HaveAPI runtime declarations are missing' unless File.file?(runtime_types)

Dir.mktmpdir('haveapi-typescript-wire-') do |directory|
  HaveAPI::TypeScriptClient::Emitter.new(emitter_ir, runtime_import: 'haveapi-client').files.each do |path, content|
    target = File.join(directory, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
  File.write(File.join(directory, 'package.json'), JSON.generate(type: 'module'))
  File.write(File.join(directory, 'tsconfig.json'), JSON.generate({
    compilerOptions: {
      target: 'ES2022', module: 'NodeNext', moduleResolution: 'NodeNext', strict: true,
      exactOptionalPropertyTypes: true, noUncheckedIndexedAccess: true, verbatimModuleSyntax: true,
      types: [], lib: %w[ES2022 DOM], outDir: './compiled', paths: { 'haveapi-client' => [runtime_types] }
    }, include: ['**/*.ts']
  }))
  output, status = Open3.capture2e(node, compiler, '-p', File.join(directory, 'tsconfig.json'))
  abort(output) unless status.success?
  unless system(node, File.join(__dir__, 'actual_runtime_wire.mjs'), File.join(directory, 'compiled/index.js'), runtime)
    exit($?.exitstatus || 1)
  end
end
