require 'require_all'
require 'date'

module HaveAPI
  module Client
    # Shortcut to HaveAPI::Client::Client.new
    def self.new(*args)
      HaveAPI::Client::Client.new(*args)
    end
  end
end

require_rel 'client/*.rb'
require_rel 'client/authentication/'
require_rel 'client/parameters/'
require_rel 'client/validators/'
