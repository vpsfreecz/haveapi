require_relative 'lib/haveapi/rust_client/version'

Gem::Specification.new do |spec|
  spec.name = 'haveapi-rust-client'
  spec.version = HaveAPI::RustClient::VERSION
  spec.authors = ['Jakub Skokan']
  spec.email = ['jakub.skokan@vpsfree.cz']
  spec.summary = 'Typed Rust client generator for HaveAPI'
  spec.description = 'Generate self-contained async and blocking Rust clients from saved HaveAPI descriptions.'
  spec.homepage = 'https://github.com/vpsfreecz/haveapi'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'
  spec.files = Dir.chdir(__dir__) do
    files = Dir['{bin,lib,template}/**/*', 'runtime/src/runtime/**/*', 'README.md', 'docs/*.md', 'LICENSE.txt']
            .select { |path| File.file?(path) }
    # RubyGems must reject a build without the prepared provenance input.
    (files + ['Gemfile.lock']).sort
  end
  spec.bindir = 'bin'
  spec.executables = ['haveapi-rust-client']
  spec.require_paths = ['lib']
  spec.add_dependency 'fiddle', '~> 1.1', '>= 1.1.8'
  spec.add_dependency 'haveapi-client', '~> 0.31.0'
  spec.add_dependency 'tomlrb', '~> 2.0'
end
