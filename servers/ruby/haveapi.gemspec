lib = File.expand_path('lib', __dir__)
$:.unshift(lib) unless $:.include?(lib)
require 'haveapi/version'

Gem::Specification.new do |s|
  s.name        = 'haveapi'
  s.version     = HaveAPI::VERSION
  s.summary     =
    s.description = 'Framework for creating self-describing APIs'
  s.authors     = 'Jakub Skokan'
  s.email       = 'jakub.skokan@vpsfree.cz'
  s.files       = `git ls-files -z`.split("\x0") + Dir.glob('doc/*')
  s.license     = 'MIT'

  s.required_ruby_version = ">= #{File.read('../../.ruby-version').strip}"

  s.add_dependency 'activesupport', '>= 7.1'
  s.add_dependency 'github-markdown'
  s.add_dependency 'haveapi-client', '~> 0.23.0'
  s.add_dependency 'json'
  s.add_dependency 'mail'
  s.add_dependency 'nesty', '~> 1.0'
  s.add_dependency 'rack-oauth2', '~> 2.2.0'
  s.add_dependency 'rake'
  s.add_dependency 'redcarpet', '~> 3.6'
  s.add_dependency 'require_all', '~> 2.0.0'
  s.add_dependency 'sinatra', '~> 3.1.0'
  s.add_dependency 'sinatra-contrib', '~> 3.1.0'
  s.add_dependency 'tilt', '~> 2.3.0'
end
