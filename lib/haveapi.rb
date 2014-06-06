require 'require_all'
require 'active_record'
require 'paper_trail'
require 'sinatra/base'
require 'sinatra/activerecord'
require 'pp'

module HaveAPI
  module Actions
  end
end

require_rel 'haveapi/*.rb'
require_rel 'haveapi/params'
require_rel 'haveapi/actions/*.rb'
