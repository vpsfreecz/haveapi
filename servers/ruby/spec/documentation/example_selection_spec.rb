require 'spec_helper'

RSpec.describe HaveAPI::DocumentationHelpers do
  api do
    define_resource(:Widget) do
      version 1
      auth false
      define_action(:Show) do
        route ''
        http_method :get
        input(:hash) { string :name }
        output(:hash) { string :name }
        authorize { allow }
        # rubocop:disable RSpec/NoExpectationExample
        example 'Request' do
          request(name: 'example')
          response(name: 'example')
        end
        # rubocop:enable RSpec/NoExpectationExample

        def exec
          { name: 'example' }
        end
      end
    end
  end

  let(:generated) { false }
  let(:server) do
    HaveAPI::Server.new(self.class::ApiModule).tap do |api|
      api.use_version(1)
      api.documentation_clients(1, typescript: { package_name: 'example-client' }) if generated
      api.mount('/api/')
    end
  end
  let(:app) { server.app }

  def example_form
    last_response.body[%r{<form\b[^>]*data-example-preferences[^>]*>.*?</form>}m]
  end

  def native_submit(**changes)
    form = example_form
    fields = form.scan(/<input\b[^>]*type="hidden"[^>]*name="([^"]+)"[^>]*value="([^"]*)"/).to_h
    form.scan(%r{<select\b([^>]*)>(.*?)</select>}m).each do |attributes, options|
      next if attributes.include?('disabled')

      name = attributes[/name="([^"]+)"/, 1]
      selected = options[/<option value="([^"]*)" selected/, 1] || options[/<option value="([^"]*)"/, 1]
      fields[name] = CGI.unescapeHTML(selected)
    end
    changes.each { |key, value| fields[key.to_s] = value }
    action = CGI.unescapeHTML(form[/action="([^"]+)"/, 1])
    get "#{action}?#{URI.encode_www_form(fields)}"
  end

  def open_panels
    last_response.body.scan(/<details\b[^>]*data-example-panel[^>]*>/).grep(/\sopen>/)
  end

  it 'submits a real GET form with only validated page, search and explicit locale fields' do
    get '/api/v1/?resource=widget&q=name&doc_lang=cs&token=ignored&extra=ignored'
    expect(example_form).to include('method="get" action="/api/v1/"', 'name="example_language"', 'name="example_client"',
                                    'name="example_detail"', 'data-apply-examples>')
    expect(example_form).to include('name="resource" value="widget"', 'name="q" value="name"', 'name="doc_lang" value="cs"')
    expect(example_form).not_to include('name="token"', 'name="extra"')
    native_submit(example_language: 'javascript')
    expect(last_request.params).to include('resource' => 'widget', 'q' => 'name', 'doc_lang' => 'cs')
    expect(last_response.body).to include('<html lang="cs">')
    expect(open_panels).to all(include('data-client="javascript-callback"', 'data-detail="simple"'))
  end

  it 'lets a new language win over the previously submitted client and applies its variant and detail next' do
    get '/api/v1/?resource=widget'
    native_submit(example_language: 'javascript')
    expect(example_form).to include('value="javascript-callback" selected', 'value="javascript-async"')
    native_submit(example_client: 'javascript-async', example_detail: 'thorough')
    expect(open_panels).not_to be_empty
    expect(open_panels).to all(include('data-client="javascript-async"', 'data-detail="thorough"'))
    expect(last_response.body).to include('id="example-widget-show-0-0"', 'data-client="python-sync"')
    expect(last_response.headers['Set-Cookie'].to_s).not_to include('haveapi.docs.preferences')
  end

  it 'infers language from a valid client and handles singleton detail with a submitted hidden value' do
    get '/api/v1/?resource=widget&q=name&doc_lang=cs&example_client=python-async'
    expect(example_form).to include('value="python" selected', 'value="python-async" selected')
    native_submit(example_language: 'curl', example_detail: 'thorough')
    expect(example_form).to include('<label data-detail-control hidden>')
    expect(example_form).to match(/data-detail-select name="example_detail" disabled/)
    expect(example_form).to include('type="hidden" name="example_detail" value="simple"')
    expect(open_panels).to all(include('data-client="5"', 'data-detail="simple"'))
    native_submit
    expect(last_request.params).to include('example_detail' => 'simple', 'resource' => 'widget', 'q' => 'name', 'doc_lang' => 'cs')
    expect(last_request.query_string.scan('example_detail=').length).to eq(1)
    native_submit(example_language: 'ruby')
    expect(example_form).to include('<label data-detail-control>')
    expect(example_form).not_to include('type="hidden" name="example_detail"')
    expect(example_form).not_to match(/data-detail-select[^>]*disabled/)
    native_submit(example_detail: 'thorough')
    expect(last_request.params['example_detail']).to eq('thorough')
    expect(last_request.query_string.scan('example_detail=').length).to eq(1)
    expect(open_panels).to all(include('data-client="0"', 'data-detail="thorough"'))
  end

  it 'falls back for unavailable profiles and unknown scalars without selecting arbitrary classes' do
    get '/api/v1/?example_client=go&example_detail=unknown'
    expect(open_panels).to all(include('data-client="0"', 'data-detail="simple"'))
    expect(last_response.body).not_to include('data-client="go"')
    get '/api/v1/?example_language=stale&example_client=python-async'
    expect(example_form).to include('value="ruby" selected')
    expect(open_panels).to all(include('data-client="0"'))
  end

  it 'rejects repeated, bracketed and invalidly encoded example selectors' do
    %w[example_language=python&example_language=ruby example_client=0&example_client=2
       example_detail=simple&example_detail=thorough example_language[]=ruby example_client[]=0 example_detail[x]=simple
       example_language=%FF example_client=%FF example_detail=%FF example_detail=%].each do |query|
      get "/api/v1/?#{query}"
      expect(last_response.status).to eq(400), query
    end
  end

  it 'uses per-group detail fallback and preserves every executable block when selection changes' do
    get '/api/v1/?page=authentication&example_client=javascript-async&example_detail=thorough'
    expect(last_response).to be_ok
    get '/api/v1/?example_client=javascript-callback&example_detail=thorough'
    expect(open_panels).to all(include('data-client="javascript-callback"', 'data-detail="simple"'))
    before = last_response.body.scan(%r{<pre><code[^>]*>(.*?)</code></pre>}m)
    get '/api/v1/?example_client=0'
    expect(last_response.body.scan(%r{<pre><code[^>]*>(.*?)</code></pre>}m)).to eq(before)
  end

  it 'leaves other clients collapsed when the selected client has no result in a group' do
    allow(HaveAPI::ClientExamples::RubyClient).to receive(:render).and_return(nil)
    get '/api/v1/?example_client=0'
    expect(last_response).to be_ok
    expect(open_panels).to be_empty
    expect(last_response.body).to include('data-example-unavailable', 'data-client="python-sync"')
  end

  it 'keeps a selected limitation panel open and its detail singleton submitted' do
    allow(HaveAPI::ClientExamples::RubyClient).to receive(:render).and_return(status: :limitation, reason: 'Supplied reason')
    get '/api/v1/?example_client=0&example_detail=thorough'
    expect(open_panels).to all(include('data-client="0"', 'data-detail="simple"'))
    expect(last_response.body).to include('class="client-limitation">Supplied reason')
    expect(example_form).to include('name="example_detail" value="simple"')
  end

  it 'omits the native form when no clients are available' do
    allow(HaveAPI::ClientExample).to receive(:clients).and_return([])
    get '/api/v1/?example_client=stale'
    expect(last_response).to be_ok
    expect(example_form).to be_nil
    expect(open_panels).to be_empty
  end

  it 'does not propagate detected locale or reinterpret selectors on root, actions, OPTIONS or search' do
    get '/api/v1/', {}, 'HTTP_ACCEPT_LANGUAGE' => 'cs'
    expect(example_form).not_to include('name="doc_lang"')
    get '/api/?example_client[]=0'
    expect(last_response).to be_ok
    expect(last_response.body).to include('data-page="versions"')
    get '/api/v1/widgets?example_client[]=0'
    expect(last_response).to be_ok
    options '/api/v1/?example_client[]=0'
    expect(last_response).to be_ok
    get '/api/v1/?page=resources&search_index=current&example_client[]=0'
    expect(last_response).to be_ok
    expect(last_response.body).to include('data-documentation-search-index')
  end

  context 'with an available generated TypeScript client' do
    let(:generated) { true }

    around do |example|
      path = File.expand_path('../../../../clients/typescript/lib', __dir__)
      $:.unshift(path)
      example.run
    ensure
      $:.delete(path)
    end

    it 'applies the real generated variant and keeps its initialization detail singleton usable' do
      get '/api/v1/?example_client=typescript-generated&example_detail=thorough'
      expect(last_response).to be_ok
      expect(open_panels).to all(include('data-client="typescript-generated"', 'data-detail="simple"'))
      expect(example_form).to include('value="typescript-generated" selected', 'name="example_detail" value="simple"')
      native_submit(example_detail: 'thorough')
      expect(last_response.body).to include('example-client')
    end
  end
end
