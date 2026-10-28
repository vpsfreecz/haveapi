require 'spec_helper'

RSpec.describe HaveAPI::ClientExample do
  it 'keeps built-in client IDs, order and language metadata together' do
    expected = [
      ['0', 'ruby', 'Ruby', nil],
      %w[javascript-callback javascript JavaScript Callback],
      %w[javascript-async javascript JavaScript Async],
      %w[typescript-callback typescript TypeScript Callback],
      %w[typescript-async typescript TypeScript Async],
      %w[python-sync python Python Sync],
      %w[python-async python Python Async],
      ['go', 'go', 'Go', nil],
      %w[rust-async rust Rust Async],
      %w[rust-blocking rust Rust Blocking],
      %w[typescript-generated typescript TypeScript Generated],
      ['2', 'php', 'PHP', nil], ['3', 'cli', 'CLI', nil],
      ['5', 'curl', 'curl', nil], ['6', 'http', 'HTTP', nil]
    ]
    actual = described_class.clients.map { |renderer| [renderer.id, renderer.language, renderer.language_label, renderer.variant] }
    expect(actual).to eq(expected)
  end

  it 'defaults unspecified third-party metadata to its own ID and label without inheriting a built-in group' do
    renderer = Class.new(HaveAPI::ClientExamples::PythonClient) do
      def self.label
        'Custom client'
      end
    end
    stub_const('CustomDocumentationExample', renderer)

    expect(renderer.language).to eq(renderer.id)
    expect(renderer.language_label).to eq('Custom client')
    expect(renderer.variant).to be_nil
  end

  it 'uses simple for legacy positional instances and reads thorough only from its context' do
    renderer = described_class.new('api.test', 'https://api.test/', '1')
    context = described_class::Context.new(version: '1', host: 'api.test', base_url: 'https://api.test/',
                                           version_url: 'https://api.test/v1/', description: {})
    expect(renderer.thorough?).to be(false)
    expect(renderer.with_context(context).thorough?).to be(false)
    expect(renderer.with_context(context.with(detail: :thorough)).thorough?).to be(true)
  end
end
