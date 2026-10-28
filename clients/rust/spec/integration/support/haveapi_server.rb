# frozen_string_literal: true

require 'optparse'
require_relative 'serve'
require_relative 'haveapi_fixture'

options = { mount: '/', documentation_examples: false }
OptionParser.new do |opts|
  opts.on('--mount PATH', 'Fixture API mount root') { |v| options[:mount] = v }
  opts.on('--documentation-examples', 'Use public documentation credential literals') { options[:documentation_examples] = true }
end.parse!
abort 'Invalid mount root' unless %r{\A/(?:[a-z_]+/)*\z}.match?(options[:mount])

RustClientFixtures.serve(RustClientFixtures::Haveapi.build(**options))
