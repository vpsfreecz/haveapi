require 'spec_helper'

describe HaveAPI::ClientExample do
  api do
    define_resource(:Widget) do
      version 1
      auth false

      define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
        authorize { allow }
      end

      define_action(:Show) do
        route '{widget_id}'
        http_method :get
        output(:hash) { string :name }
        authorize { allow }

        # rubocop:disable RSpec/NoExpectationExample
        example 'sample' do
          path_params 1
          response({ name: 'documented widget' })
        end
        # rubocop:enable RSpec/NoExpectationExample
      end
    end
  end

  default_version 1

  it 'keeps maintained renderers registered and removes File system' do
    labels = described_class.clients.map(&:label)
    expect(labels).to include('Ruby', 'PHP', 'CLI', 'curl', 'HTTP')
    expect(labels).not_to include('File system')
  end

  it 'omits the unmaintained client tab and overview link from generated HTML' do
    get '/v1/'

    expect(last_response.status).to eq(200)
    expect(last_response.body).not_to include('File system', 'haveapi-fs', 'FUSE-based file system')
    expect(last_response.body).to include('Initialization', '<summary>Ruby', '<summary>PHP', '<summary>curl')
  end

  it 'hides unconfigured generated SDKs in overview, initialization, authentication and actions' do
    get '/v1/'
    expect(last_response.status).to eq(200)
    expect(last_response.body).not_to include('clients/go', 'clients/rust', 'init-go', 'init-rust', 'typescript-generated', '>Go</h', '>Rust (')
    expect(last_response.body).to include('init-javascript-callback', 'init-typescript-async', 'init-python-sync')
    get '/v1/?resource=widget'
    expect(last_response.body).to include('example-widget-show-0-javascript-callback')
  end

  it 'uses the configured profile consistently for every panel and escapes limitations once' do
    profiles = { go: HaveAPI::ClientExample::Profile.new(language: :go, package_name: 'example.test/client', package_version: 'v1.2.3', adapter: Object.new) }
    allow(app.settings.api_server).to receive(:documentation_client_profiles).and_return(profiles)
    allow(HaveAPI::ClientExamples::GoClient).to receive(:render).and_return({ status: :limitation, reason: 'Unsupported <sample> & value' }.freeze)
    get '/v1/'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('clients/go', 'init-go', 'Unsupported &lt;sample&gt; &amp; value')
    expect(last_response.body).not_to include('Unsupported <sample>', 'clients/rust', 'init-rust')
    get '/v1/?resource=widget'
    expect(last_response.body).to include('example-widget-show-0-go', 'Unsupported &lt;sample&gt; &amp; value')
  end

  it 'passes mounted version-aware URLs and stable canonical action data into renderers' do
    contexts = []
    allow(HaveAPI::ClientExamples::GoClient).to receive_messages(
      available?: true,
      detail_levels_for: HaveAPI::ClientExamples::GoClient.detail_levels
    )
    allow(HaveAPI::ClientExamples::GoClient).to receive(:render) do |kind, context:, **_kwargs|
      contexts << [kind, context]
      { status: :code, code: context.version_url }
    end
    server = HaveAPI::Server.new(get_opt(:api_module))
    server.use_version(1)
    server.mount('/mounted/api/')
    response = Rack::MockRequest.new(server.app).get('/mounted/api/v1/?resource=widget', 'HTTP_HOST' => 'example.org')
    expect(response.status).to eq(200)
    selected = contexts.find { |kind, ctx| kind == :example && ctx.action_name == 'show' }.last
    expect(selected.base_url).to eq('http://example.org/mounted/api/')
    expect(selected.version_url).to eq('http://example.org/mounted/api/v1/')
    expect(selected.resource_path).to eq(['widget'])
    expect(selected.description[:resources]).to have_key('widget')
    expect(selected.sample[:response]).to eq(name: 'documented widget')
  end

  it 'prints a package identity without inventing an omitted version and escapes it once' do
    profile = HaveAPI::ClientExample::Profile.new(language: :go, package_name: 'example.test/<client>&', package_version: nil, adapter: Object.new)
    allow(app.settings.api_server).to receive(:documentation_client_profiles).and_return({ go: profile })
    allow(HaveAPI::ClientExamples::GoClient).to receive(:render).and_return({ status: :code, code: 'example' })
    get '/v1/'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('<code>example.test/&lt;client&gt;&amp;</code>')
    expect(last_response.body).not_to include('example.test/<client>', '&amp;lt;', 'version = "latest"')
  end
end
