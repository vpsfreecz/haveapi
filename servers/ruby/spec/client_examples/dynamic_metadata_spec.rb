require 'spec_helper'
require_relative 'dynamic_fixture'

RSpec.describe HaveAPI::ClientExamples::DynamicHelpers do
  include DynamicExampleFixture

  let(:renderers) do
    [HaveAPI::ClientExamples::JsClient, HaveAPI::ClientExamples::JsAsyncClient,
     HaveAPI::ClientExamples::TsClient, HaveAPI::ClientExamples::TsAsyncClient,
     HaveAPI::ClientExamples::PythonClient, HaveAPI::ClientExamples::PythonAsyncClient]
  end

  it 'limits all sample outcomes that need required global or object input metadata' do
    %i[global object].each do |scope|
      metadata = { scope => { input: { layout: :hash, namespace: false,
                                       parameters: { private_confirmation: { type: 'Boolean', required: true, default: false } } } } }
      action = dynamic_action.merge(meta: metadata)
      [true, false].each do |status|
        renderers.each do |renderer|
          result = renderer.render(:example, context: dynamic_context(action:, sample: dynamic_sample.merge(status:)))
          expect(result[:status]).to eq(:limitation)
          expect(result[:reason]).to eq('This action requires input metadata that the sample format cannot supply.')
          expect(result[:reason]).not_to include('private_confirmation', 'default')
          expect(result).not_to have_key(:code)
        end
      end
    end
  end

  it 'keeps absent, optional and output-only metadata executable without invented values' do
    [nil, {}, { global: { input: { parameters: { optional: { type: 'Boolean', required: false } } } } },
     { object: { input: { parameters: { optional: { type: 'Boolean' } } } } },
     { global: { output: { parameters: { required_output: { type: 'String', required: true } } } } }].each do |meta|
      renderers.each do |renderer|
        result = renderer.render(:example, context: dynamic_context(action: dynamic_action.merge(meta:)))
        expect(result[:status]).to eq(:code), result.inspect
        expect(result[:code]).not_to include('optional', 'required_output')
      end
    end
  end

  it 'checks string-keyed metadata and does not apply object metadata without action input' do
    action = dynamic_action.merge(meta: { 'object' => { 'input' => { 'parameters' => {
      'confirmation' => { 'type' => 'Boolean', 'required' => true }
    } } } })
    renderers.each do |renderer|
      expect(renderer.render(:example, context: dynamic_context(action:))[:status]).to eq(:limitation)
      context = dynamic_context(action: action.merge(input: nil), sample: dynamic_sample.merge(request: {}))
      expect(renderer.render(:example, context:)[:status]).to eq(:code)
    end
  end

  it 'uses only public typed literals and advertised finite machine choices for token inputs' do
    description = token_description
    fields = description[:resources][:token][:actions]['request'][:input][:parameters]
    fields[:user] = { type: 'String', required: true, default: 'PRIVATE_USER' }
    fields[:password][:default] = 'PRIVATE_PASSWORD'
    fields[:count] = { type: 'Integer', required: true, default: 99 }
    fields[:enabled] = { type: 'Boolean', required: true, validators: { accept: { value: true, message: 'PRIVATE_PROSE' } } }
    fields[:scope] = { type: 'String', required: true, validators: { include: { values: { 'all' => 'PRIVATE_LABEL' } } } }
    fields[:resource] = { type: 'Resource', required: true }
    fields[:timestamp] = { type: 'Datetime', required: true }
    fields[:custom] = { type: 'Custom', required: true }
    fields[:interval] = { type: 'Integer', required: true }
    before = Marshal.dump(description)
    renderers.each do |renderer|
      result = renderer.render(:auth, context: dynamic_context, auth_method: :token, auth_description: description)
      expect(result[:status]).to eq(:code), result.inspect
      expect(result[:code]).to include('secret', 'user', 'fixed', 'all', '2026-01-01T00:00:00Z')
      expect(result[:code]).not_to include('PRIVATE_', 'os.environ', 'credential(', 'HAVEAPI_', 'node:process')
    end
    expect(Marshal.dump(description)).to eq(before)
    helper = HaveAPI::ClientExamples::JsClient.new('api.test', 'https://api.test/', '2')
    inputs = helper.send(:auth_token_credentials, description)
    expect(inputs).to include('user' => 'user', 'password' => 'secret', 'count' => 1, 'enabled' => true,
                              'scope' => 'all', 'resource' => 1, 'custom' => {}, 'interval' => 1, 'lifetime' => 'fixed')
  end

  it 'limits unsupported required types and input shapes instead of guessing defaults or dropping fields' do
    descriptions = []
    description = token_description
    description[:resources][:token][:actions]['request'][:input][:parameters][:hidden] = {
      type: 'Unsupported', required: true, default: 'PRIVATE_DEFAULT'
    }
    descriptions << description
    description = token_description
    description[:resources][:token][:actions]['verify'][:input][:parameters][:hidden] = {
      type: 'Unsupported', required: true, default: 'PRIVATE_DEFAULT'
    }
    descriptions << description
    description = token_description
    description[:resources][:token][:actions]['request'][:input][:layout] = :object_list
    descriptions << description
    renderers.each do |renderer|
      descriptions.each do |desc|
        result = renderer.render(:auth, context: dynamic_context, auth_method: :token, auth_description: desc)
        expect(result).to include(status: :limitation)
        expect(result.inspect).not_to include('PRIVATE_DEFAULT')
      end
    end
  end

  it 'uses actual continuation action arguments and rejects unknown continuation or input names' do
    renderer = HaveAPI::ClientExamples::JsClient.new('api.test', 'https://api.test/', '2')
    options = renderer.token_login_options(token_description)
    script = <<~JS
      const assert = require('node:assert/strict');
      const options = #{options};
      assert.deepEqual(options.callback('verify', {code: {}}), {code: 'code'});
      assert.throws(() => options.callback('missing', {code: {}}), /Unknown authentication continuation/);
      assert.throws(() => options.callback('verify', {unexpected: {}}), /Unknown authentication input/);
    JS
    output, status = Open3.capture2e('node', '-e', script)
    expect(status).to be_success, output
    renderers.grep(Class).each do |client|
      source = client.render(:auth, context: dynamic_context, auth_method: :token, auth_description: token_description).fetch(:code)
      expect(source).not_to include('os.environ', 'HAVEAPI_', 'step.action')
      expect(source).to include(client.code == :python ? 'step.next_action' : '(action, parameters)')
    end
  end
end
