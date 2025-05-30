ar = Object.const_defined?(:ActiveRecord)

require 'require_all'
require 'active_support/inflector'
require 'active_record' if ar
require 'sinatra/base'
require 'sinatra/cookies'
require 'sinatra/activerecord' if ar
require 'json'

module HaveAPI
  module Resources; end
  module Actions; end
end

require_relative 'haveapi/params'
require_rel 'haveapi/parameters/'
require_rel 'haveapi/*.rb'
require_rel 'haveapi/actions/*.rb'
require_rel 'haveapi/resources/*.rb'
require_rel 'haveapi/model_adapters/hash'
require_rel 'haveapi/model_adapters/active_record' if ar
require_rel 'haveapi/authentication'
require_rel 'haveapi/output_formatters/base.rb'
require_rel 'haveapi/output_formatters/'
require_rel 'haveapi/validators/'
require_rel 'haveapi/client_examples/'
require_rel 'haveapi/extensions'
