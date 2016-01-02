require 'bundler/gem_tasks'
require 'rspec/core'
require 'rspec/core/rake_task'
require 'rdoc/task'
require 'active_support/core_ext/string/inflections'
require 'haveapi'
require 'haveapi/tasks/hooks'

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
end

RDoc::Task.new do |rdoc|
  rdoc.main = "README.md"
  rdoc.rdoc_files.include('README.md', 'lib/haveapi/*.rb', 'lib/haveapi/**/*.rb')
  rdoc.options << '--line-numbers' << '--page-dir=doc'

  document_hooks(rdoc)
end
