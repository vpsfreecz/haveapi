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
end
