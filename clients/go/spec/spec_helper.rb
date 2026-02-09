# frozen_string_literal: true

require 'bundler/setup'
require 'open3'
require 'tmpdir'
require 'haveapi/go_client'

require_relative 'support/test_server'

TEST_SERVER = ClientTestServer.new

RSpec.configure do |config|
  config.order = :random

  config.before(:suite) do
    TEST_SERVER.start
  end

  config.after(:suite) do
    TEST_SERVER.stop!
  end

  config.before do
    TEST_SERVER.reset!
  end
end
