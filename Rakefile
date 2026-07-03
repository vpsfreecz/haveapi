require_relative 'utils/i18n/catalog'

namespace :i18n do
  desc 'Generate package-local translation artifacts from i18n/haveapi.yml'
  task :update do
    HaveAPI::I18n::Catalog.new(root: __dir__).update!
  end

  desc 'Check translation coverage and generated artifacts'
  task :health do
    HaveAPI::I18n::Catalog.new(root: __dir__).check!
  end
end
