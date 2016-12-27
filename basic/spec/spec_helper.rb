require 'haveapi'
require 'haveapi/spec/helpers'
require_relative '../lib/api'

ENV['RACK_ENV'] = 'test'

# Configure specs
RSpec.configure do |config|
  config.order = 'random'

  config.extend HaveAPI::Spec::ApiBuilder
  config.include HaveAPI::Spec::SpecMethods
end
