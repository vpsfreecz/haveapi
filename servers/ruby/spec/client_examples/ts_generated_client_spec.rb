require 'spec_helper'

class TypeScriptDocumentationAdapterFixture
  def render(kind:, context:, mode:, auth_method: nil, auth_description: nil); end
end

describe HaveAPI::ClientExamples::TsGeneratedClient do
  let(:adapter) { instance_spy(TypeScriptDocumentationAdapterFixture) }
  let(:profile) { Struct.new(:language, :adapter).new(:typescript, adapter).freeze }
  let(:context) do
    HaveAPI::ClientExample::Context.new(
      version: '1.0', host: 'example.test', base_url: 'https://example.test/mount/',
      version_url: 'https://example.test/mount/v1.0/', description: {},
      resource_path: ['widget'], action_name: 'update', action: {}, sample: { request: {} }, profile:
    )
  end

  it 'adds a separate generated variant while preserving dynamic TypeScript identifiers' do
    expect(described_class.id).to eq('typescript-generated')
    expect(described_class.label).to eq('TypeScript (generated)')
    expect(described_class.code).to eq(:typescript)
    expect(HaveAPI::ClientExamples::TsClient.id).to eq('typescript-callback')
    expect(HaveAPI::ClientExamples::TsAsyncClient.id).to eq('typescript-async')
  end

  it 'is available only for a matching optional profile' do
    expect(described_class.available?(nil)).to be(false)
    expect(described_class.available?(context.with(profile: nil))).to be(false)
    expect(described_class.available?(context.with(profile: Struct.new(:language).new(:rust)))).to be(false)
    expect(described_class.available?(context)).to be(true)
  end

  it 'delegates the immutable authorized context and exact authentication metadata' do
    result = { status: :code, code: 'generated TypeScript' }.freeze
    allow(adapter).to receive(:render).and_return(result)
    expect(described_class.render(:init, context:)).to eq(result)
    expect(described_class.render(:auth, context:, auth_method: :token, auth_description: { http_header: 'X-Token' })).to eq(result)
    expect(adapter).to have_received(:render).with(kind: :init, context:, mode: :async)
    expect(adapter).to have_received(:render).with(kind: :auth, context:, mode: :async, auth_method: :token,
                                                   auth_description: { http_header: 'X-Token' })
  end

  it 'binds only the supplied authorized sample and preserves limitations' do
    sample = { request: { label: 'public' } }
    result = { status: :limitation, reason: 'The saved SDK does not represent this sample.' }.freeze
    allow(adapter).to receive(:render).and_return(result)
    renderer = described_class.new('example.test', 'https://example.test/', '1.0').with_context(context)
    expect(renderer.example(sample)).to eq(result)
    expect(adapter).to have_received(:render).with(kind: :example, mode: :async, context: have_attributes(sample: sample))
    expect(renderer.init).to eq(result)
    expect(described_class.new('example.test', 'https://example.test/', '1.0').init).to include(status: :limitation)
  end
end
