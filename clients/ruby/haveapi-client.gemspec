lib = File.expand_path('lib', __dir__)
$:.unshift(lib) unless $:.include?(lib)
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

  spec.required_ruby_version = '>= 3.0'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport', '>= 7.0'
  spec.add_dependency 'highline', '~> 2.1.0'
  spec.add_dependency 'json'
  spec.add_dependency 'require_all', '~> 2.0.0'
  spec.add_dependency 'rest-client', '~> 2.1.0'
  spec.add_dependency 'ruby-progressbar', '~> 1.13.0'
end
