# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'haveapi/client/version'

Gem::Specification.new do |spec|
  spec.name          = 'haveapi-client'
  spec.version       = HaveAPI::Client::VERSION
  spec.authors       = ['Jakub Skokan']
  spec.email         = ['jakub.skokan@vpsfree.cz']
  spec.summary       =
  spec.description   = 'Ruby API and CLI for HaveAPI'
  spec.homepage      = ''
  spec.license       = 'GPL'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.6'
  spec.add_development_dependency 'rake'

  spec.add_runtime_dependency 'activesupport', '~> 4.1.0'
  spec.add_runtime_dependency 'require_all', '~> 1.3.0'
  spec.add_runtime_dependency 'rest_client', '~> 1.7.3'
  spec.add_runtime_dependency 'json', '~> 1.8.1'
  spec.add_runtime_dependency 'highline', '~> 1.6.21'
  spec.add_runtime_dependency 'table_print', '~> 1.5.1'
end
