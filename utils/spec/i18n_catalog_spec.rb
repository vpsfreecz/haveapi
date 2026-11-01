require 'rspec'
require 'tmpdir'
require_relative '../i18n/catalog'

RSpec.describe HaveAPI::I18n::Catalog do
  let(:root) { Dir.mktmpdir('haveapi-i18n-') }
  let(:catalog) { described_class.new(root:) }

  after { FileUtils.remove_entry(root) }

  def write_source(path, source)
    target = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, source)
  end

  def write_catalog(documentation)
    locales = %w[en cs].to_h do |locale|
      [locale, { 'haveapi' => { 'documentation' => documentation }, 'haveapi_client' => {} }]
    end
    write_source('i18n/haveapi.yml', YAML.dump(locales))
    catalog.update!
  end

  {
    'servers/ruby/lib/haveapi/views/page.erb' => "<%= documentation_t('labels.missing') %>",
    'servers/ruby/lib/haveapi/documentation_helpers.rb' => "documentation_t('labels.missing')",
    'servers/ruby/lib/haveapi/public/js/documentation.js' => "documentationMessage('missing')",
    'servers/ruby/lib/haveapi/documentation_validators.rb' => "text('missing')"
  }.each do |path, source|
    it "checks translation calls in #{path}" do
      write_catalog('labels' => { 'known' => 'Known' })
      write_source(path, source)

      expect { catalog.check! }.to raise_error(/missing translation key haveapi\.documentation\..*missing/)
    end
  end

  it 'accepts translated browser subtrees and literal consumers' do
    write_catalog('browser' => { 'copied' => 'Copied' })
    write_source('servers/ruby/lib/haveapi/views/page.erb', "documentation_t('browser')")
    write_source('servers/ruby/lib/haveapi/public/js/documentation.js', "documentationMessage('copied')")

    expect(catalog.check!).to be(true)
  end

  it 'distinguishes documentation storage names from message keys' do
    write_catalog('browser' => { 'copied' => 'Copied' })
    write_source('servers/ruby/lib/haveapi/public/js/documentation.js', <<~JS)
      var storageKey = 'haveapi.docs.preferences.v1';
      var cookie = 'haveapi.docs.locale';
      documentationMessage('copied');
    JS

    expect(catalog.check!).to be(true)
  end

  it 'checks placeholder parity in documentation messages' do
    locales = {
      'en' => { 'haveapi' => { 'documentation' => { 'label' => 'For %{name}' } }, 'haveapi_client' => {} },
      'cs' => { 'haveapi' => { 'documentation' => { 'label' => 'Pro %{other}' } }, 'haveapi_client' => {} }
    }
    write_source('i18n/haveapi.yml', YAML.dump(locales))
    catalog.update!

    expect { catalog.check! }.to raise_error(/interpolation mismatch for haveapi\.documentation\.label/)
  end

  [
    'servers/ruby/lib/haveapi/client_examples/ruby.rb',
    'clients/go/lib/haveapi/go_client/documentation.rb',
    'clients/rust/lib/haveapi/rust_client/documentation.rb',
    'clients/typescript/lib/haveapi/typescript_client/documentation.rb'
  ].each do |path|
    it "checks literal example-comment keys in #{path}" do
      write_catalog('comments' => { 'known' => 'Known' })
      write_source(path, "context.example_comment('missing', default: 'Original comment')")

      expect { catalog.check! }.to raise_error(/missing translation key haveapi\.documentation\.comments\.missing/)
    end
  end

  it 'accepts catalog-backed example comments with interpolation' do
    write_catalog('comments' => { 'read' => 'Read %{resource}' })
    write_source('servers/ruby/lib/haveapi/client_examples/ruby.rb', <<~RUBY)
      example_comment 'read', default: 'Read %{resource}', resource: 'widget'
    RUBY
    write_source('clients/go/lib/haveapi/go_client/documentation.rb', <<~RUBY)
      context.example_comment(
        'read', default: 'Read %{resource}', resource: 'widget'
      )
    RUBY

    expect(catalog.check!).to be(true)
  end

  {
    'servers/ruby/lib/haveapi/documentation_context.rb' => "documentation_message('generated.go.missing', default: 'Original text')",
    'clients/go/lib/haveapi/go_client/documentation.rb' => "unsupported!('generated.go.missing', default: 'Original text')",
    'clients/rust/lib/haveapi/rust_client/documentation.rb' => "unsupported!('generated.rust.missing', default: 'Original text')",
    'clients/typescript/lib/haveapi/typescript_client/documentation.rb' => "documentation_message('generated.typescript.missing', default: 'Original text')"
  }.each do |path, call|
    it "checks generated-client prose keys in #{path}" do
      write_catalog('generated' => { 'known' => 'Known' })
      write_source(path, call)

      expect { catalog.check! }.to raise_error(/missing translation key haveapi\.documentation\.generated\..*missing/)
    end
  end
end
