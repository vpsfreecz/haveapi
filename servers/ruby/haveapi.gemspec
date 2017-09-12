lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'haveapi/version'

Gem::Specification.new do |s|
  s.name        = 'haveapi'
  s.version     = HaveAPI::VERSION
  s.date        = '2017-09-12'
  s.summary     =
  s.description = 'Framework for creating self-describing APIs'
  s.authors     = 'Jakub Skokan'
  s.email       = 'jakub.skokan@vpsfree.cz'
  s.files       = `git ls-files -z`.split("\x0")
  s.license     = 'MIT'

  s.required_ruby_version = '>= 2.0.0'

  s.add_runtime_dependency 'require_all'
  s.add_runtime_dependency 'json'
  s.add_runtime_dependency 'activesupport', '>= 4.0'
  s.add_runtime_dependency 'sinatra', '~> 1.4'
  s.add_runtime_dependency 'tilt', '~> 1.4'
  s.add_runtime_dependency 'redcarpet', '~> 3.4'
  s.add_runtime_dependency 'rake'
  s.add_runtime_dependency 'github-markdown'
  s.add_runtime_dependency 'nesty', '~> 1.0'
  s.add_runtime_dependency 'haveapi-client', '~> 0.10.0'
  s.add_runtime_dependency 'mail'
end
