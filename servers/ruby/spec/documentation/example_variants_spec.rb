require 'spec_helper'

RSpec.describe HaveAPI::Server::ServerHelpers, '#documentation_example_variants' do
  let(:context) do
    HaveAPI::ClientExample::Context.new(version: 1, host: 'example.test', base_url: 'https://example.test/',
                                        version_url: 'https://example.test/v1/', description: { resources: {}, authentication: {} })
  end
  let(:view) { Object.new.extend(described_class).extend(HaveAPI::DocumentationHelpers) }
  let(:client) do
    Class.new(HaveAPI::ClientExample) do
      id 'custom'
      def self.render(kind, context:, **)
        return { status: :limitation, reason: 'Simple limitation' }.freeze if kind == :init && context.detail == :simple

        { status: :code, code: "#{kind}:#{context.detail}" }.freeze
      end
    end
  end

  before do
    allow(view).to receive(:documentation_clients).and_return([client])
    allow(view).to receive(:documentation_context) { |_client, **changes| context.with(**changes) }
  end

  it 'renders Simple once and only declared Thorough while preserving custom limitation behavior' do
    allow(client).to receive(:render).and_call_original
    allow(client).to receive(:detail_levels_for).and_call_original
    variants = view.documentation_example_variants(:init)
    expect(variants.map { |_client, detail, result| [detail, result[:status]] }).to eq([%i[simple limitation], %i[thorough code]])
    expect(client).to have_received(:render).with(:init, context: have_attributes(detail: :simple), auth_method: nil, auth_description: nil).once
    expect(client).to have_received(:render).with(:init, context: have_attributes(detail: :thorough), auth_method: nil, auth_description: nil).once
    expect(client).to have_received(:detail_levels_for).with(:init, context: have_attributes(detail: :simple),
                                                                    result: variants.first.last, auth_method: nil, auth_description: nil).once
    expect(view.documentation_client_metadata.first[:details]).to eq(%w[simple thorough])
    expect(context.detail).to eq(:simple)
    expect(context.description).to eq(resources: {}, authentication: {})
  end

  it 'collects an ordered page union without a prepass or speculative rendering' do
    allow(client).to receive(:detail_levels_for) { |kind, **| kind == :init ? [:simple].freeze : %i[simple thorough].freeze }
    allow(client).to receive(:render).and_call_original
    expect(view.documentation_client_metadata.first[:details]).to eq(['simple'])
    expect(client).not_to have_received(:render)
    expect(view.documentation_example_variants(:init).map { |_client, detail, _result| detail }).to eq([:simple])
    expect(view.documentation_client_metadata.first[:details]).to eq(['simple'])
    expect(view.documentation_example_variants(:example).map { |_client, detail, _result| detail }).to eq(%i[simple thorough])
    expect(view.documentation_client_metadata.first[:details]).to eq(%w[simple thorough])
    expect(view.documentation_example_variants(:init).length).to eq(1)
    expect(view.documentation_client_metadata.first[:details]).to eq(%w[simple thorough])
  end

  it 'keeps absent results absent without querying capabilities or advertising a group' do
    allow(client).to receive(:render).and_return(nil)
    allow(client).to receive(:detail_levels_for).and_call_original
    expect(view.documentation_example_variants(:init)).to be_empty
    expect(client).not_to have_received(:detail_levels_for)
    expect(view.documentation_client_metadata.first[:details]).to eq(['simple'])
  end

  it 'rejects malformed custom capability returns rather than inventing a fallback' do
    [nil, [], [:thorough], ['simple'], %i[thorough simple], %i[simple simple]].each do |levels|
      allow(client).to receive(:detail_levels_for).and_return(levels)
      expect { view.documentation_example_variants(:init) }.to raise_error(ArgumentError, 'Invalid documentation example detail levels')
    end
  end

  it 'preserves legacy adapter HTML panels when its Simple limitation has distinct Thorough output' do
    adapter = Object.new
    def adapter.resolve(**)
      nil
    end

    def adapter.render(kind:, context:, **)
      return { status: :limitation, reason: 'Legacy Simple limitation' } if context.detail == :simple

      { status: :code, code: "legacy #{kind} thorough" }
    end
    profile = HaveAPI::ClientExample::Profile.new(language: :typescript, package_name: 'legacy-client', package_version: nil, adapter:)
    server = HaveAPI::Server.new(Module.new)
    server.use_version(1)
    allow(server).to receive(:documentation_client_profiles).and_return(typescript: profile)
    server.mount('/')
    response = Rack::MockRequest.new(server.app).get('/v1/', 'HTTP_HOST' => 'example.test')
    expect(response.status).to eq(200)
    group = response.body.match(%r{data-example-details="([^"]*)" id="init-examples">(.*?)</div>}m)
    expect(JSON.parse(CGI.unescapeHTML(group[1])).fetch('typescript-generated')).to eq(%w[simple thorough])
    expect(group[2]).to include('id="init-typescript-generated"', 'Legacy Simple limitation',
                                'id="init-typescript-generated-thorough"', 'legacy init thorough')
    panels = group[2].scan(/data-client="typescript-generated"[^>]*data-detail="([^"]+)"/).flatten
    expect(panels).to eq(%w[simple thorough])
    expect(adapter).not_to respond_to(:detail_levels_for)
  end
end
