# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe HaveAPI::Client do
  it 'requires the Ruby client without predefining HaveAPI' do
    lib = File.expand_path('../lib', __dir__)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      '-I',
      lib,
      '-e',
      "require 'haveapi/client'; puts HaveAPI::Client::VERSION"
    )

    expect(status).to be_success, stderr
    expect(stdout).to include(HaveAPI::Client::VERSION)
  end
end
