require_relative 'lib/haveapi/typescript_client/version'

Gem::Specification.new do |spec|
  spec.name = 'haveapi-typescript-client'
  spec.version = HaveAPI::TypeScriptClient::VERSION
  spec.authors = ['Jakub Skokan']
  spec.summary = 'Generate typed TypeScript operations from saved HaveAPI schemas'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'
  spec.files = Dir.chdir(__dir__) do
    Dir['{bin,lib,template}/**/*', 'README.md', 'LICENSE.txt'].select { |path| File.file?(path) }.sort
  end
  spec.bindir = 'bin'
  spec.executables = ['haveapi-typescript-client']
  spec.require_paths = ['lib']
  spec.add_dependency 'haveapi-client', '~> 0.30.0'
end
