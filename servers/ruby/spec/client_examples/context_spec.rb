require 'spec_helper'

describe HaveAPI::ClientExample::Context do
  let(:description) { { resources: { widget: { actions: {} } } } }
  let(:context) do
    described_class.new(version: '1', host: 'api.test', base_url: 'https://api.test/mount/',
                        version_url: 'https://api.test/mount/v1/', description:)
  end

  it 'copies and freezes request data without freezing the source description' do
    expect(context.description).to be_frozen
    expect(context.description[:resources]).to be_frozen
    expect(description[:resources]).not_to be_frozen
    description[:resources][:secret] = {}
    expect(context.description[:resources]).not_to have_key(:secret)
  end

  it 'keeps per-example state independent and leaves the original context intact' do
    data = { request: { name: 'safe' } }
    child = context.with(resource_path: ['widget'], action_name: 'show', sample: data)
    data[:request][:name].replace('changed')
    expect(child.sample[:request][:name]).to eq('safe')
    expect(context.sample).to be_nil
    expect(child.resource_path).to eq(['widget'])
    expect(child).to be_frozen
  end

  it 'preserves legacy initialization constructors and wraps plain source' do
    renderer = Class.new(HaveAPI::ClientExample) do
      def initialize(host, base_url, version)
        raise ArgumentError, 'expected API version 1' unless version == '1'

        super
      end

      def init
        "#{base_url}v#{version}/"
      end
    end
    result = renderer.render(:init, context:)
    expect(result).to eq(status: :code, code: 'https://api.test/mount/v1/')
    expect(result).to be_frozen
    expect(result[:code]).to be_frozen
  end

  it 'preserves request/response renderers and nil legacy authentication' do
    renderer = Class.new(HaveAPI::ClientExample) do
      def request(_sample)
        'request'
      end

      def response(_sample)
        'response'
      end
    end
    expect(renderer.render(:example, context:)).to eq(status: :code, code: "request\n\nresponse")
    expect(renderer.render(:auth, context:, auth_method: :basic, auth_description: {})).to be_nil
  end

  it 'wraps a limitation without allowing HTML or an invalid result contract' do
    renderer = Class.new(HaveAPI::ClientExample) do
      def init
        { status: :limitation, reason: 'Cannot render <this>' }
      end
    end
    expect(renderer.render(:init, context:)).to eq(status: :limitation, reason: 'Cannot render <this>')
  end
end
