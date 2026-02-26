lib = File.expand_path('lib', __dir__)
$:.unshift(lib) unless $:.include?(lib)
require 'haveapi/go_client/version'

Gem::Specification.new do |spec|
  spec.name          = 'haveapi-go-client'
  spec.version       = HaveAPI::GoClient::VERSION
  spec.authors       = ['Jakub Skokan']
  spec.email         = ['jakub.skokan@vpsfree.cz']
  spec.summary       =
    spec.description = 'Go client generator'
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.required_ruby_version = ">= #{File.read('../../.ruby-version').strip}"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'haveapi-client', '~> 0.27.3'
end
