require 'spec_helper'

describe HaveAPI::DocumentationHelpers, '#render_version_documentation' do
  empty_api
  use_version 1

  def overview(response = last_response)
    expect(response.status).to eq(200)
    response.body.match(%r{<section id="client-libraries">(.*?)</section>}m).to_a.fetch(1)
  end

  def library_entries(body)
    body.scan(%r{<li>(.*?)</li>}m).flatten.map { |entry| CGI.unescapeHTML(entry.gsub(/<[^>]*>/, '')).strip }
  end

  def profile(language, name, version = nil)
    adapter = Object.new
    def adapter.render(**)
      { status: :limitation, reason: 'Fixture API client sample is unavailable.' }
    end
    HaveAPI::ClientExample::Profile.new(language:, package_name: name, package_version: version, adapter:)
  end

  def use_profiles(profiles)
    allow(app.settings.api_server).to receive(:documentation_client_profiles).and_return(profiles)
  end

  it 'links every available maintained dynamic client and both execution styles to its guide' do
    get '/v1/'
    body = overview
    {
      'clients/ruby#client-library' => 'library',
      'clients/ruby#cli' => 'CLI',
      'clients/js#javascript-with-callbacks' => 'callback',
      'clients/js#javascript-with-async-await' => 'async',
      'clients/js#typescript-with-callbacks' => 'callback',
      'clients/js#typescript-with-async-await' => 'async',
      'clients/python#synchronous-client' => 'sync',
      'clients/python#asynchronous-client' => 'async',
      'clients/php' => 'PHP'
    }.each do |path, label|
      expect(body).to include("href=\"https://github.com/vpsfreecz/haveapi/tree/master/#{path}\">#{label}</a>")
    end
    expect(library_entries(body)).to eq(['Ruby (library and CLI)', 'JavaScript (callback and async)',
                                         'TypeScript (callback and async)', 'Python (sync and async)', 'PHP'])
    expect(body).not_to include('clients/go', 'clients/rust', 'clients/typescript', 'Elixir', 'File system')
  end

  it 'shows configured API client identities and only their explicitly configured versions' do
    use_profiles(go: profile(:go, 'example.test/widget/client', 'v2.3.4'),
                 rust: profile(:rust, 'widget-client'),
                 typescript: profile(:typescript, '@example/widget', '1.2.3'))
    get '/v1/'
    body = overview
    expect(body).to include('clients/go', 'example.test/widget/client', 'v2.3.4', 'clients/rust', 'widget-client',
                            'clients/typescript', '@example/widget', '1.2.3')
    expect(body.scan('@example/widget').length).to eq(1)
    expect(body.scan('widget-client').length).to eq(1)
    expect(body.scan('example.test/widget/client').length).to eq(1)
    expect(body.scan('v2.3.4').length).to eq(1)
    expect(body.scan('1.2.3').length).to eq(1)
    expect(body).not_to include('latest', '0.0.0')
    entries = library_entries(body)
    expect(entries.length).to eq(7)
    expect(entries.grep(/\ATypeScript/)).to eq(['TypeScript (callback, async and API client): @example/widget 1.2.3'])
    expect(entries.grep(/\ARust/)).to eq(['Rust (async and blocking): widget-client'])
  end

  it 'does not advertise unavailable API client renderers or unsupported profiles' do
    use_profiles(go: profile(:go, 'HIDDEN_SDK_IDENTITY'), elixir: profile(:elixir, 'UNSUPPORTED_SDK_IDENTITY'))
    allow(HaveAPI::ClientExamples::GoClient).to receive(:available?).and_return(false)
    get '/v1/'
    body = overview
    expect(body).not_to include('HIDDEN_SDK_IDENTITY', 'UNSUPPORTED_SDK_IDENTITY', 'clients/go', 'clients/elixir')
    expect(body).to include('Ruby', 'Python (')
  end

  it 'filters dynamic client links through the same availability contract' do
    allow(HaveAPI::ClientExamples::PythonAsyncClient).to receive(:available?).and_return(false)
    get '/v1/'
    expect(library_entries(overview)).to include('Python (sync)')
    expect(overview).not_to include('#asynchronous-client')
  end

  it 'omits unavailable generated variants without hiding their remaining language choices' do
    use_profiles(rust: profile(:rust, 'visible-rust-sdk'), typescript: profile(:typescript, 'HIDDEN_TYPESCRIPT_SDK'))
    allow(HaveAPI::ClientExamples::TsGeneratedClient).to receive(:available?).and_return(false)
    allow(HaveAPI::ClientExamples::RustBlockingClient).to receive(:available?).and_return(false)
    get '/v1/'
    body = overview
    entries = library_entries(body)
    expect(entries.grep(/\ATypeScript/)).to eq(['TypeScript (callback and async)'])
    expect(entries.grep(/\ARust/)).to eq(['Rust (async): visible-rust-sdk'])
    expect(body).not_to include('HIDDEN_TYPESCRIPT_SDK', 'clients/typescript', '>blocking</a>')
    expect(body.scan('visible-rust-sdk').length).to eq(1)
  end

  it 'keeps Ruby and CLI independently discoverable when only one is available' do
    allow(HaveAPI::ClientExamples::RubyClient).to receive(:available?).and_return(false)
    get '/v1/'
    entries = library_entries(overview)
    expect(entries).to include('CLI')
    expect(entries.grep(/\ARuby/)).to be_empty
    allow(HaveAPI::ClientExamples::RubyClient).to receive(:available?).and_return(true)
    allow(HaveAPI::ClientExamples::RubyCli).to receive(:available?).and_return(false)
    get '/v1/'
    entries = library_entries(overview)
    expect(entries).to include('Ruby')
    expect(entries).not_to include('CLI', 'Ruby (library and CLI)')
  end

  it 'escapes renderer labels and configured API client identities and versions' do
    payload = '<script>injected</script> & "quoted"'
    use_profiles(go: profile(:go, payload, payload))
    allow(HaveAPI::ClientExamples::GoClient).to receive(:language_label).and_return(payload)
    allow(HaveAPI::ClientExamples::RubyClient).to receive(:language_label).and_return(payload)
    allow(HaveAPI::ClientExamples::PythonAsyncClient).to receive(:variant).and_return(payload)
    get '/v1/'
    body = overview
    expect(body).not_to include(payload, '<script>', 'href="javascript:')
    expect(body).to include('&lt;script&gt;injected&lt;/script&gt; &amp; &quot;quoted&quot;')
    expect(body).to include('href="https://github.com/vpsfreecz/haveapi/tree/master/clients/go"')
  end

  it 'makes curl and raw HTTP examples discoverable without claiming client packages' do
    get '/v1/'
    body = overview
    expect(body).to include('href="/v1/?page=resources">curl</a>', 'href="/v1/?page=resources">HTTP</a>',
                            'request examples are available on resource pages.')
    expect(body).not_to include('clients/curl', 'clients/http')
  end

  it 'keeps local discovery links within the mounted API and Rack prefix' do
    server = HaveAPI::Server.new(get_opt(:api_module))
    server.use_version(1)
    server.default_version = 1
    server.mount('/mounted/api/')
    response = Rack::MockRequest.new(server.app).get('/mounted/api/v1/',
                                                     'HTTP_HOST' => 'example.test', 'SCRIPT_NAME' => '/rack')
    body = overview(response)
    expect(body).to include('href="/rack/mounted/api/v1/?page=resources">curl</a>')
    expect(body).to include('href="/rack/mounted/api/v1/?page=resources">HTTP</a>')
    expect(body).to include('href="https://github.com/vpsfreecz/haveapi/tree/master/clients/ruby#client-library">library</a>')
  end
end
