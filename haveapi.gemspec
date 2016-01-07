lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'haveapi/version'

Gem::Specification.new do |s|
  s.name        = 'haveapi'
  s.version     = HaveAPI::VERSION
  s.date        = '2015-08-13'
  s.summary     =
  s.description = 'Framework for creating self-describing APIs'
  s.authors     = 'Jakub Skokan'
  s.email       = 'jakub.skokan@vpsfree.cz'
  s.files       = `git ls-files -z`.split("\x0")
  s.license     = 'MIT'

  s.required_ruby_version = '~> 2.0'

  s.add_runtime_dependency 'require_all'
  s.add_runtime_dependency 'json'
  s.add_runtime_dependency 'sinatra', '~> 1.4.6'
  s.add_runtime_dependency 'rake'
  s.add_runtime_dependency 'github-markdown', '~> 0.6.9'
end
