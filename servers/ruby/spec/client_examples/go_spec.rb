require 'haveapi/documentation_context'
require 'haveapi/documentation_clients'
require 'haveapi/client_examples/go_client'

RSpec.describe HaveAPI::ClientExamples::GoClient do
  let(:result) { { status: :code, code: 'package main' }.freeze }
  let(:adapter) do
    contract = Class.new do
      def render(**); end
    end
    instance_double(contract, render: result)
  end
  let(:profile) { Struct.new(:language, :adapter).new(:go, adapter) }
  let(:context) do
    HaveAPI::ClientExample::Context.new(
      version: '7', host: 'api.example.test', base_url: 'https://api.example.test/mounted/',
      version_url: 'https://api.example.test/mounted/v7/', description: {},
      resource_path: %w[widget], action_name: 'update', action: {},
      sample: { status: true, request: { enabled: false } }, profile:
    )
  end

  it 'registers the frozen Go ID and requires its configured profile' do
    expect(described_class.id).to eq('go')
    expect(described_class.code).to eq(:go)
    expect(described_class.order).to eq(16)
    expect(described_class).to be_available(context)
    expect(described_class).not_to be_available(context.with(profile: nil))
    expect(described_class).not_to be_available(context.with(profile: Struct.new(:language).new(:rust)))
  end

  it 'delegates initialization without requiring the optional generator gem' do
    expect(described_class.render(:init, context:)).to eq(result)
    expect(adapter).to have_received(:render).with(kind: :init, context:, mode: :sync)
  end

  it 'delegates advertised authentication with its filtered descriptor' do
    descriptor = { description: 'HTTP Basic authentication' }
    expect(described_class.render(:auth, context:, auth_method: :basic, auth_description: descriptor)).to eq(result)
    expect(adapter).to have_received(:render).with(kind: :auth, context:, mode: :sync,
                                                   auth_method: :basic, auth_description: descriptor)
  end

  it 'binds the selected filtered example and preserves plain limitation results' do
    limitation = { status: :limitation, reason: 'This Go SDK input is unsupported.' }.freeze
    allow(adapter).to receive(:render).and_return(limitation)
    expect(described_class.render(:example, context:)).to eq(limitation)
    expect(adapter).to have_received(:render) do |**arguments|
      selected = arguments.fetch(:context)
      expect(arguments[:kind]).to eq(:example)
      expect(arguments[:mode]).to eq(:sync)
      expect(selected.sample).to eq(context.sample)
      expect(selected.sample).to be_frozen
      expect(selected.description).to eq(context.description)
    end
  end
end
