# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'haveapi/client/version'

Gem::Specification.new do |spec|
  spec.name          = 'haveapi-client'
  spec.version       = HaveAPI::Client::VERSION
  spec.date          = '2018-03-14'
  spec.authors       = ['Jakub Skokan']
  spec.email         = ['jakub.skokan@vpsfree.cz']
  spec.summary       =
  spec.description   = 'Ruby API and CLI for HaveAPI'
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.6'
  spec.add_development_dependency 'rake'

  spec.add_runtime_dependency 'activesupport', '>= 4.0'
  spec.add_runtime_dependency 'require_all', '~> 1.5.0'
  spec.add_runtime_dependency 'rest-client', '~> 2.0.2'
  spec.add_runtime_dependency 'json'
  spec.add_runtime_dependency 'highline', '~> 1.7.8'
  spec.add_runtime_dependency 'ruby-progressbar', '~> 1.7.5'
end
