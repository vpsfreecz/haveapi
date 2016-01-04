require 'bundler/gem_tasks'
require 'rspec/core'
require 'rspec/core/rake_task'
require 'yard'
require 'active_support/core_ext/string/inflections'
require 'haveapi'
require 'haveapi/tasks/hooks'

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
end

YARD::Rake::YardocTask.new do |t|
  t.files   = ['lib/**/*.rb']
  t.options = ['--protected', '--output-dir=html_doc', '--files=doc/*.md']
  t.before = document_hooks
end
