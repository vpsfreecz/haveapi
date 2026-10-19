# frozen_string_literal: true

require 'rspec'
require_relative 'run'

RSpec.describe RustClientIntegration do
  it 'registers fixture actions and preserves the server string validation contract' do
    fixture = File.expand_path('support/haveapi_fixture.rb', __dir__)
    probe = <<~RUBY
      require ARGV.fetch(0)
      RustClientFixtures::Haveapi.extend_resources!
      resource = HaveAPI::ClientTestAPI::Resources::RustFixture
      actions = []
      resource.actions { |action| actions << action.action_name }
      required_input = HaveAPI::ClientTestAPI::Resources::Test::Echo.input
      required_input.exec
      values = {i: 0, f: 0.0, b: false, dt: '2020-01-31T10:20Z', s: '', t: 'text'}
      invalid = []
      begin
        required_input.validate({required_input.namespace => values.dup})
      rescue HaveAPI::ValidationError => e
        invalid = e.to_hash.keys.map(&:to_s)
      end
      optional_input = resource::Echo.input
      optional_input.exec
      valid = required_input.validate({required_input.namespace => values.merge(s: 'scalar')})
      optional = optional_input.validate({optional_input.namespace => {text: ''}})
      delete_input = resource::DeleteBody.input
      delete_input.exec
      delete_values = {number: nil, zero: 0, flag: false, text: '', value: {'nested' => [0, false, nil]}}
      deleted = delete_input.validate({delete_input.namespace => delete_values})
      puts JSON.generate(
        actions: actions,
        empty_required_errors: invalid,
        nonempty_required: valid.fetch(required_input.namespace).fetch(:s),
        empty_optional: optional.fetch(optional_input.namespace).fetch(:text),
        delete_method: resource::DeleteBody.http_method,
        delete_input: deleted.fetch(delete_input.namespace)
      )
    RUBY
    stdout, stderr, status = Bundler.with_unbundled_env do
      Open3.capture3(
        { 'BUNDLE_GEMFILE' => RustClientIntegration::SERVER_GEMFILE,
          'GEM_HOME' => RustClientIntegration::SERVER_GEM_HOME, 'GEM_PATH' => nil },
        'bundle', 'exec', RbConfig.ruby, '-e', probe, fixture
      )
    end

    expect(status.success?).to be(true), stderr
    contract = JSON.parse(stdout)
    expect(contract.fetch('actions')).to include('EchoCustom', 'CustomQuery', 'Query', 'DeleteBody')
    expect(contract.fetch('empty_required_errors')).to eq(['s'])
    expect(contract.fetch('nonempty_required')).to eq('scalar')
    expect(contract.fetch('empty_optional')).to eq('')
    expect(contract.fetch('delete_method')).to eq('delete')
    expect(contract.fetch('delete_input')).to eq(
      'number' => nil, 'zero' => 0, 'flag' => false, 'text' => '',
      'value' => { 'nested' => [0, false, nil] }
    )
  end
end
