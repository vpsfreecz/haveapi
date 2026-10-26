require_relative 'typescript_client/version'

module HaveAPI
  module TypeScriptClient
    class Error < StandardError; end
  end
end

require_relative 'typescript_client/snapshot'
require_relative 'typescript_client/naming'
require_relative 'typescript_client/ir'
require_relative 'typescript_client/generator'
