# ActiveRecord must be required before HaveAPI
require 'active_record'
require 'haveapi'

module API
  # API resources are stored in this module
  module Resources ; end

  # Authentication backends
  module Authentication ; end

  # When a resource has no version set, this one will be used
  HaveAPI.implicit_version = '1.0'

  # Return API server with a default configuration
  # @return [HaveAPI::Server]
  def self.default
    api = HaveAPI::Server.new(Resources)

    # Include all detected API versions
    api.use_version(:all)

    # Register authentication backends
    api.auth_chain << Authentication::Basic
    api.auth_chain << Authentication::Token

    # Register routes for all actions
    api.mount('/')

    api
  end
end

require_rel '../models'
require_rel 'api/resources'
require_rel 'api/authentication'
