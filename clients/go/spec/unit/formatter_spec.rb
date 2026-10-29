require 'haveapi/go_client'

RSpec.describe HaveAPI::GoClient::Generator do
  let(:generator) { described_class.allocate }

  before do
    allow(generator).to receive(:dst).and_return('/generated/client')
  end

  it 'reports an unsuccessful go fmt operation' do
    allow(generator).to receive(:system).with('go', 'fmt', chdir: '/generated/client').and_return(false)

    expect { generator.go_fmt }.to raise_error(RuntimeError, 'go fmt failed')
  end

  it 'reports an unavailable Go executable' do
    allow(generator).to receive(:system).with('go', 'fmt', chdir: '/generated/client').and_return(nil)

    expect { generator.go_fmt }.to raise_error(RuntimeError, 'go fmt failed')
  end
end
