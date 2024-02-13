lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'haveapi/client/version'

Gem::Specification.new do |spec|
  spec.name          = 'haveapi-client'
  spec.version       = HaveAPI::Client::VERSION
  spec.authors       = ['Jakub Skokan']
  spec.email         = ['jakub.skokan@vpsfree.cz']
  spec.summary       =
    spec.description = 'Ruby API and CLI for HaveAPI'
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.2.0'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'activesupport', '>= 7.0'
  spec.add_runtime_dependency 'highline', '~> 2.1.0'
  spec.add_runtime_dependency 'json'
  spec.add_runtime_dependency 'require_all', '~> 2.0.0'
  spec.add_runtime_dependency 'rest-client', '~> 2.1.0'
  spec.add_runtime_dependency 'ruby-progressbar', '~> 1.13.0'
end
