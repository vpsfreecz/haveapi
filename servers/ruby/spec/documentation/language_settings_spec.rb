require 'spec_helper'

describe HaveAPI::Server do
  api do
    define_resource(:Ping) do
      version 1
      auth false
      define_action(:Show) do
        route 'ping'
        http_method :get
        output(:hash) { string :value }
        authorize { allow }
        def exec
          { value: 'pong' }
        end
      end
    end
  end

  let(:server) do
    described_class.new(get_opt(:api_module)).tap do |api|
      api.use_version(1)
      api.mount('/api/')
    end
  end

  def request(path)
    Rack::MockRequest.new(server.app).get(path, 'HTTP_HOST' => 'example.test')
  end

  %w[/api/v1/ /api/ /api/doc/protocol].each do |path|
    it "keeps a native language form above Theme on #{path}" do
      response = request("#{path}?doc_lang=cs")
      expect(response.status).to eq(200)
      body = response.body
      form = body[%r{<form data-documentation-language\b.*?</form>}m]
      expect(form).to include('method="get"', "action=\"#{path}\"", '<label for="docs-language">Jazyk</label>',
                              '<select id="docs-language" name="doc_lang">',
                              '<option value="en">English</option>', '<option value="cs" selected>Česky</option>')
      button = form[%r{<button\b[^>]*data-documentation-language-submit[^>]*>.*?</button>}m]
      expect(button).to include('type="submit"', '>Použít jazyk</button>')
      expect(button).not_to match(/\bhidden\b|display:\s*none/)
      expect(form.index('</select>')).to be < form.index('<button')
      expect(body.index(form)).to be < body.index('id="docs-theme-label"')
      expect(form).not_to include('value="auto"')
    end
  end

  it 'submits the native form without JavaScript while retaining the page and query' do
    response = request('/api/v1/?resource=ping&q=hostname')
    form = response.body[%r{<form data-documentation-language\b.*?</form>}m]
    action = CGI.unescapeHTML(form[/action="([^"]+)"/, 1])
    fields = form.scan(/type="hidden" name="([^"]+)" value="([^"]*)"/).map do |name, value|
      [CGI.unescapeHTML(name), CGI.unescapeHTML(value)]
    end
    expect(fields).to include(%w[resource ping], %w[q hostname])
    selected = request("#{action}?#{URI.encode_www_form(fields + [%w[doc_lang cs]])}")

    expect(selected.status).to eq(200)
    expect(selected.body).to include('<html lang="cs">', 'data-resource="ping"', 'name="q" value="hostname"')
    expect(selected['Set-Cookie'].to_s).to include('haveapi.docs.locale=cs')
  end

  it 'uses the short Czech label only for the programming language selector' do
    response = request('/api/v1/?doc_lang=cs')
    expect(response.body).to include('<label>Jazyk <select data-language-select>')
    expect(response.body).not_to include('Programovací jazyk <select')
    expect(request('/api/v1/?doc_lang=en').body).to include('<label>Programming language <select data-language-select>')
  end

  it 'styles every breadcrumb with the same marker while translating its accessible name' do
    { 'en' => 'Breadcrumb', 'cs' => 'Drobečková navigace' }.each do |locale, label|
      ['/api/v1/?page=authentication', '/api/v1/?resource=ping', '/api/doc/protocol?'].each do |path|
        separator = path.end_with?('?') ? '' : '&'
        response = request("#{path}#{separator}doc_lang=#{locale}")
        expect(response.status).to eq(200)
        expect(response.body).to include("<nav class=\"docs-breadcrumb\" aria-label=\"#{label}\"")
        expect(response.body.scan('class="docs-breadcrumb"').length).to eq(1)
      end
    end
  end

  it 'shows the API address without the redundant client link or usage permissions sentence' do
    { 'en' => 'The API is available at', 'cs' => 'API je dostupné na' }.each do |locale, address|
      response = request("/api/v1/?doc_lang=#{locale}")
      main = response.body[%r{<main\b.*?</main>}m]
      expect(main).to include("<p>#{address} <code>http://example.test/api/</code>.</p>")
      expect(main).not_to include('href="https://github.com/vpsfreecz/haveapi"',
                                  'Each API request still checks permissions', 'Každý požadavek API nadále ověřuje oprávnění')
      expect(main).to include('Projdi si všechny zdroje') if locale == 'cs'
    end
  end

  it 'localizes generated-client labels and JS variants while preserving machine identifiers and packages' do
    adapter = Object.new
    def adapter.render(**)
      { status: :limitation, reason: 'Fixture sample is unavailable.' }.freeze
    end
    profiles = %i[go rust typescript].to_h do |language|
      [language, HaveAPI::ClientExample::Profile.new(language:, package_name: "#{language}-package", package_version: '1.2.3', adapter:)]
    end
    allow(server).to receive(:documentation_client_profiles).and_return(profiles)
    {
      'en' => ['Go API client', 'Rust API client (async)', 'Rust API client (blocking)', 'TypeScript API client', 'Async', 'Blocking', 'API client'],
      'cs' => ['Klient API pro Go', 'Klient API pro Rust (asynchronní)', 'Klient API pro Rust (blokující)', 'Klient API pro TypeScript', 'Asynchronní', 'Blokující', 'Klient API']
    }.each do |locale, text|
      response = request("/api/v1/?doc_lang=#{locale}")
      body = response.body
      expect(response.status).to eq(200)
      text.first(4).each { |label| expect(body).to include("<summary>#{label} · ") }
      metadata = JSON.parse(body[%r{<script[^>]*data-documentation-clients>(.*?)</script>}m, 1]).to_h { |client| [client.fetch('id'), client] }
      expect(metadata.fetch('go')).to include('language' => 'go', 'language_label' => 'Go', 'variant' => nil)
      %w[rust-async rust-blocking typescript-generated].each_with_index do |id, index|
        expect(metadata.fetch(id).fetch('variant')).to eq(text[index + 4])
        expect(body).to include("data-client=\"#{id}\"")
      end
      expect(body).to include('data-variant="Async"', 'data-variant="Blocking"', 'data-variant="API client"',
                              'go-package', 'rust-package', 'typescript-package', '1.2.3')
    end
  end

  it 'keeps custom-renderer display labels and variants unchanged in every locale' do
    helper = Object.new.extend(HaveAPI::DocumentationHelpers).extend(HaveAPI::DocumentationLocale)
    custom = Struct.new(:id, :label, :variant).new('custom-generated', '<Custom & label>', '<Custom & variant>')
    %i[en cs].each do |locale|
      I18n.with_locale(locale) do
        expect(helper.documentation_client_label(custom)).to eq(custom.label)
        expect(helper.documentation_client_variant(custom)).to eq(custom.variant)
      end
    end
  end
end
