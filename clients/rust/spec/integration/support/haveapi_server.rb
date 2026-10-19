# frozen_string_literal: true

require 'optparse'
require_relative 'serve'
require_relative 'haveapi_fixture'

options = { mount: '/' }
OptionParser.new do |opts|
  opts.on('--mount PATH', 'Fixture API mount root') { |v| options[:mount] = v }
end.parse!
abort 'Invalid mount root' unless %r{\A/(?:[a-z_]+/)*\z}.match?(options[:mount])

RustClientFixtures.serve(RustClientFixtures::Haveapi.build(mount: options.fetch(:mount)))
