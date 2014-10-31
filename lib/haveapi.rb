require 'require_all'
require 'active_record'
require 'sinatra/base'
require 'sinatra/activerecord'
require 'pp'
require 'github/markdown'

module HaveAPI
  module Actions
  end
end

require_relative 'haveapi/params'
require_rel 'haveapi/params/'
require_rel 'haveapi/*.rb'
require_rel 'haveapi/model_adapters/'
require_rel 'haveapi/authentication'
require_rel 'haveapi/actions/*.rb'
require_rel 'haveapi/output_formatters/base.rb'
require_rel 'haveapi/output_formatters/'
require_rel 'haveapi/extensions'

