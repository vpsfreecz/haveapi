require 'digest'
require_relative 'client/version'

module HaveAPI
  module Schema
    class Error < StandardError; end

    def self.source_identity
      root = __dir__
      digest = Digest::SHA256.new
      %w[haveapi/client/version.rb haveapi/schema.rb haveapi/schema/capture.rb
         haveapi/schema/fetch_command.rb haveapi/schema/snapshot.rb].sort.each do |logical|
        digest.update(logical).update("\0").update(File.binread(File.join(root, '..', logical))).update("\0")
      end
      {
        'package_name' => 'haveapi-client'.freeze,
        'version' => HaveAPI::Client::VERSION,
        'source_sha256' => digest.hexdigest.freeze
      }.freeze
    end
  end
end

require_relative 'schema/snapshot'
require_relative 'schema/capture'
require_relative 'schema/fetch_command'
