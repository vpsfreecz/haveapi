require 'spec_helper'

describe HaveAPI::ClientExample do
  api do
    define_resource(:Widget) do
      version 1
      auth false

      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        authorize { allow }
      end
    end
  end

  default_version 1

  it 'keeps maintained renderers registered and removes File system' do
    labels = described_class.clients.map(&:label)
    expect(labels).to include('Ruby', 'JavaScript', 'PHP', 'CLI', 'curl', 'HTTP')
    expect(labels).not_to include('File system')
  end

  it 'omits the unmaintained client tab and overview link from generated HTML' do
    get '/v1/'

    expect(last_response.status).to eq(200)
    expect(last_response.body).not_to include('File system', 'haveapi-fs', 'FUSE-based file system')
    expect(last_response.body).to include('Initialization', '<h4>Ruby</h4>', '<h4>PHP</h4>', '<h4>curl</h4>')
  end
end
