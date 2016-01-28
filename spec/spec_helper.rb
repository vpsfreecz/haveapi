require 'require_all'
require_relative '../lib/haveapi'
require_rel '../lib/haveapi/spec/*.rb'

module HaveAPI
  module Spec
    module API

    end
  end
end

require_rel 'api'

# Configure specs
RSpec.configure do |config|
  config.order = 'random'

  config.extend HaveAPI::Spec::ApiBuilder
  config.include HaveAPI::Spec::SpecMethods
end
