require_relative 'rust_client/version'

module HaveAPI
  module RustClient
    class Error < StandardError; end
  end
end

require_relative 'rust_client/snapshot'
require_relative 'rust_client/naming'
require_relative 'rust_client/ir'
require_relative 'rust_client/model'
require_relative 'rust_client/generator'
