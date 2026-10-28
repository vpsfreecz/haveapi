require 'spec_helper'
require 'haveapi/documentation_context'
require 'haveapi/client_examples/rust_client'

class RustDocumentationAdapterFixture
  def detail_levels_for(kind:, context:, result:, mode:, auth_method: nil, auth_description: nil); end

  def render(kind:, context:, mode:, auth_method: nil, auth_description: nil); end
end

describe HaveAPI::ClientExamples::RustClient do
  let(:adapter) { instance_spy(RustDocumentationAdapterFixture) }
  let(:profile) { Struct.new(:language, :adapter).new(:rust, adapter).freeze }
  let(:context) do
    HaveAPI::ClientExample::Context.new(
      version: '1.0', host: 'example.test', base_url: 'https://example.test/mount/',
      version_url: 'https://example.test/mount/v1.0/', description: {},
      resource_path: ['widget'], action_name: 'update', action: {}, sample: { request: {} }, profile:
    )
  end
  let(:code) { { status: :code, code: 'generated Rust' }.freeze }

  it 'registers separate stable variants sharing the Rust grammar' do
    expect(HaveAPI::ClientExamples::RustAsyncClient.id).to eq('rust-async')
    expect(HaveAPI::ClientExamples::RustBlockingClient.id).to eq('rust-blocking')
    expect(HaveAPI::ClientExamples::RustAsyncClient.code).to eq(:rust)
    expect(HaveAPI::ClientExamples::RustBlockingClient.code).to eq(:rust)
    expect(HaveAPI::ClientExamples::RustAsyncClient.order).to eq(17)
    expect(HaveAPI::ClientExamples::RustBlockingClient.order).to eq(18)
  end

  it 'hides all Rust variants without the matching configured profile' do
    [HaveAPI::ClientExamples::RustAsyncClient, HaveAPI::ClientExamples::RustBlockingClient].each do |renderer|
      expect(renderer.available?(context.with(profile: nil))).to be(false)
      expect(renderer.available?(context.with(profile: Struct.new(:language).new(:go)))).to be(false)
      expect(renderer.available?(context)).to be(true)
    end
  end

  it 'passes immutable authorized init context to the pure adapter' do
    allow(adapter).to receive(:render).and_return(code)
    expect(HaveAPI::ClientExamples::RustAsyncClient.render(:init, context:)).to eq(code)
    expect(adapter).to have_received(:render).with(kind: :init, context:, mode: :async)
  end

  it 'keeps authentication provider and description exact for blocking rendering' do
    allow(adapter).to receive(:render).and_return(code)
    expect(HaveAPI::ClientExamples::RustBlockingClient.render(
             :auth, context:, auth_method: :token, auth_description: { http_header: 'X-Token' }
           )).to eq(code)
    expect(adapter).to have_received(:render).with(kind: :auth, context:, mode: :blocking,
                                                   auth_method: :token, auth_description: { http_header: 'X-Token' })
  end

  it 'binds the exact filtered sample when using the retained positional API' do
    sample = { request: { name: 'authorized' } }
    renderer = HaveAPI::ClientExamples::RustAsyncClient.new('example.test', 'https://example.test/', '1.0')
    renderer.with_context(context)
    allow(adapter).to receive(:render).and_return(code)
    expect(renderer.example(sample)).to eq(code)
    expect(adapter).to have_received(:render).with(kind: :example, mode: :async, context: have_attributes(sample: sample))
    expect(renderer.context.sample).to be_frozen
  end

  it 'preserves a concise adapter limitation without fabricating source' do
    result = { status: :limitation, reason: 'This sample needs an unsupported API client capability.' }.freeze
    allow(adapter).to receive(:render).and_return(result)
    expect(HaveAPI::ClientExamples::RustAsyncClient.render(:example, context:)).to eq(result)
  end

  it 'retains callable legacy constructor methods even without a profile' do
    renderer = HaveAPI::ClientExamples::RustAsyncClient.new('example.test', 'https://example.test/', '1.0')
    expect(renderer.init).to include(status: :limitation)
    expect(renderer.auth(:basic, {})).to include(status: :limitation)
    expect(renderer.example({})).to include(status: :limitation)
  end

  it 'delegates each mode capability with the exact Simple result without rerendering or mutating context' do
    description = { http_header: 'X-Token' }.freeze
    [HaveAPI::ClientExamples::RustAsyncClient, HaveAPI::ClientExamples::RustBlockingClient].each do |renderer|
      allow(adapter).to receive(:detail_levels_for).and_return(%i[simple thorough].freeze)
      levels = renderer.detail_levels_for(:auth, context:, result: code,
                                                 auth_method: :token, auth_description: description)
      expect(levels).to eq(%i[simple thorough])
      expect(levels).to be_frozen
      expect(adapter).to have_received(:detail_levels_for).with(
        kind: :auth, context:, result: code, mode: renderer.rust_mode,
        auth_method: :token, auth_description: description
      )
    end
    expect(adapter).not_to have_received(:render)
    expect(context.detail).to eq(:simple)
    expect(context.profile.adapter).to equal(adapter)
  end

  it 'delegates limitation policy and rejects malformed modern levels instead of falling back' do
    renderer = HaveAPI::ClientExamples::RustAsyncClient
    limitation = { status: :limitation, reason: 'Unsupported sample' }.freeze
    allow(adapter).to receive(:detail_levels_for).and_return([:simple].freeze)
    expect(renderer.detail_levels_for(:example, context:, result: limitation)).to eq([:simple])
    expect(adapter).to have_received(:detail_levels_for).with(
      kind: :example, context:, result: limitation, mode: :async, auth_method: nil, auth_description: nil
    )
    [nil, [], [:thorough], %i[thorough simple], %i[simple simple], ['simple']].each do |invalid|
      allow(adapter).to receive(:detail_levels_for).and_return(invalid)
      expect { renderer.detail_levels_for(:example, context:, result: code) }.to raise_error(ArgumentError)
    end
  end
end
