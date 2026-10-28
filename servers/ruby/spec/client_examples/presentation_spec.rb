require 'spec_helper'
require 'tmpdir'

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
      ['typescript-generated', 'typescript', 'TypeScript', 'API client'],
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

  it 'defaults undeclared custom renderers to both frozen detail levels' do
    renderer = Class.new(described_class)
    expect(renderer.detail_levels).to eq(%i[simple thorough])
    expect(renderer.detail_levels).to be_frozen
    expect { renderer.detail_levels << :other }.to raise_error(FrozenError)
  end

  it 'inherits the nearest detail declaration and freezes an independently owned override' do
    parent = Class.new(described_class)
    levels = [:simple]
    parent.detail_levels(*levels)
    levels << :thorough
    child = Class.new(parent)
    grandchild = Class.new(child)
    expect(child.detail_levels).to equal(parent.detail_levels)
    expect(grandchild.detail_levels).to eq([:simple])
    child.detail_levels :simple, :thorough
    expect(child.detail_levels).to be_frozen
    expect(grandchild.detail_levels).to equal(child.detail_levels)
    expect(parent.detail_levels).to eq([:simple])
  end

  it 'rejects unsupported, duplicate, reversed and non-symbol detail declarations without changing metadata' do
    renderer = Class.new(described_class)
    renderer.detail_levels :simple
    [[:thorough], %i[thorough simple], %i[simple simple], %i[simple thorough thorough],
     [:other], ['simple'], [nil], [[:simple]]].each do |values|
      expect { renderer.detail_levels(*values) }.to raise_error(ArgumentError)
      expect(renderer.detail_levels).to eq([:simple])
    end
  end

  it 'declares one format for HTTP, inherited curl and CLI without changing registry IDs or other clients' do
    single_level = [HaveAPI::ClientExamples::Http, HaveAPI::ClientExamples::Curl, HaveAPI::ClientExamples::RubyCli]
    registry = described_class.clients
    single_level.each do |renderer|
      expect(renderer.detail_levels).to eq([:simple])
      expect(renderer.detail_levels).to be_frozen
    end
    expect(HaveAPI::ClientExamples::Curl.detail_levels).to equal(HaveAPI::ClientExamples::Http.detail_levels)
    (registry - single_level).each { |renderer| expect(renderer.detail_levels).to eq(%i[simple thorough]) }
    expect(described_class.clients).to eq(registry)
  end

  it 'uses simple for legacy positional instances and reads thorough only from its context' do
    renderer = described_class.new('api.test', 'https://api.test/', '1')
    context = described_class::Context.new(version: '1', host: 'api.test', base_url: 'https://api.test/',
                                           version_url: 'https://api.test/v1/', description: {})
    expect(renderer.thorough?).to be(false)
    expect(renderer.with_context(context).thorough?).to be(false)
    expect(renderer.with_context(context.with(detail: :thorough)).thorough?).to be(true)
  end

  it 'keeps a custom Simple limitation and its distinct thorough result under the legacy declaration' do
    renderer = Class.new(described_class) do
      def init
        thorough? ? 'custom recovery instructions' : { status: :limitation, reason: 'custom Simple limitation' }
      end
    end
    context = described_class::Context.new(version: '1', host: 'api.test', base_url: 'https://api.test/',
                                           version_url: 'https://api.test/v1/', description: {})
    result = renderer.render(:init, context:)
    expect(result).to include(status: :limitation)
    expect(renderer.detail_levels_for(:init, context:, result:)).to equal(renderer.detail_levels)
    expect(renderer.render(:init, context: context.with(detail: :thorough))).to include(code: 'custom recovery instructions')
    renderer.detail_levels :simple
    expect(renderer.detail_levels_for(:init, context:, result:)).to equal(renderer.detail_levels)
    expect(context.detail).to eq(:simple)
  end

  it 'retains inherited legacy declarations for every wrapper without invoking the adapter' do
    calls = []
    adapter = Class.new do
      define_method(:resolve) { |**| calls << :resolve }
      define_method(:render) { |**| calls << :render }
    end.new.freeze
    limitation = { status: :limitation, reason: 'Simple format unavailable' }.freeze
    [[HaveAPI::ClientExamples::GoClient, :go],
     [HaveAPI::ClientExamples::RustAsyncClient, :rust],
     [HaveAPI::ClientExamples::RustBlockingClient, :rust],
     [HaveAPI::ClientExamples::TsGeneratedClient, :typescript]].each do |wrapper, language|
      profile = described_class::Profile.new(language:, package_name: 'fixture-client', package_version: nil, adapter:)
      context = described_class::Context.new(version: '1', host: 'api.test', base_url: 'https://api.test/',
                                             version_url: 'https://api.test/v1/', description: {}, profile:)
      child = Class.new(wrapper)
      expect(child.detail_levels_for(:init, context:, result: limitation)).to equal(wrapper.detail_levels)
      expect(child.detail_levels_for(:init, context:, result: limitation)).to eq(%i[simple thorough])
      child.detail_levels :simple
      expect(child.detail_levels_for(:init, context:, result: limitation)).to equal(child.detail_levels)
      expect(child.detail_levels_for(:init, context:, result: limitation)).to be_frozen
      expect(context.profile).to equal(profile)
      expect(context.profile.adapter).to equal(adapter)
    end
    expect(calls).to be_empty
  end

  it 'keeps a pinned saved-profile adapter with only resolve/render through actual wrapper selection' do
    calls = []
    adapter = Class.new do
      define_method(:resolve) { |**| calls << :resolve }
      define_method(:render) do |kind:, context:, mode:, **|
        calls << [kind, context.detail, mode]
        if context.detail == :thorough
          { status: :code, code: 'legacy recovery instructions' }.freeze
        else
          { status: :limitation, reason: 'legacy Simple limitation' }.freeze
        end
      end
    end.new
    profiles = described_class::Profiles.new
    generator = Module.new
    generator.const_set(:VERSION, '0.29.0')
    documentation = Class.new
    generator.const_set(:Documentation, documentation)
    stub_const('HaveAPI::GoClient', generator)
    allow(profiles).to receive(:require).with('haveapi/go_client/documentation').and_return(true)
    allow(documentation).to receive(:new).and_return(adapter)
    Dir.mktmpdir('haveapi-legacy-detail-') do |directory|
      path = File.join(directory, 'description.json')
      File.write(path, JSON.generate(resources: {}, authentication: {}, meta: { namespace: '_meta' }))
      profiles.register(1, go: { import_path: 'example.test/client', description_path: path,
                                 generator_version: '0.29.0' })
      profiles.mount([1])
      server = instance_double(HaveAPI::Server)
      profiles.finalize(server)
      profile = profiles.for_version(1).fetch(:go)
      context = described_class::Context.new(version: '1', host: 'api.test', base_url: 'https://api.test/',
                                             version_url: 'https://api.test/v1/', description: {}, profile:)
      wrapper = HaveAPI::ClientExamples::GoClient
      simple = wrapper.render(:init, context:)
      levels = wrapper.detail_levels_for(:init, context:, result: simple)
      expect(levels).to eq(%i[simple thorough])
      expect(levels).to be_frozen
      expect(calls).to eq([%i[init simple sync]])
      panels = levels.map do |detail|
        [detail, detail == :simple ? simple : wrapper.render(:init, context: context.with(detail:))]
      end
      expect(panels).to eq([
                             [:simple, { status: :limitation, reason: 'legacy Simple limitation' }],
                             [:thorough, { status: :code, code: 'legacy recovery instructions' }]
                           ])
      expect(calls).to eq([%i[init simple sync], %i[init thorough sync]])
      expect(profile.adapter).to equal(adapter)
      expect(profile).to be_frozen
      expect(adapter).to be_frozen
      expect(adapter).not_to respond_to(:detail_levels_for)
      expect(context.detail).to eq(:simple)
      expect(documentation).to have_received(:new).once
    end
  end

  it 'delegates modern limitation queries exactly once and propagates exceptions and invalid levels' do
    wrapper = HaveAPI::ClientExamples::GoClient
    adapter = Object.new
    def adapter.detail_levels_for(**); end
    allow(adapter).to receive(:detail_levels_for).and_return([:simple])
    context = Object.new.freeze
    result = { status: :limitation, reason: 'current limitation' }.freeze
    auth_description = { http_header: 'X-Token' }.freeze
    levels = wrapper.adapter_detail_levels_for(adapter:, kind: :auth, context:, result:, mode: :sync,
                                               auth_method: :token, auth_description:)
    expect(levels).to eq([:simple])
    expect(levels).to be_frozen
    expect(adapter).to have_received(:detail_levels_for).once.with(
      kind: :auth, context:, result:, mode: :sync, auth_method: :token, auth_description:
    )
    [nil, [], [:thorough], %i[thorough simple], %i[simple simple], ['simple']].each do |invalid|
      allow(adapter).to receive(:detail_levels_for).and_return(invalid)
      expect do
        wrapper.adapter_detail_levels_for(adapter:, kind: :init, context:, result:, mode: :sync)
      end.to raise_error(ArgumentError)
    end
    failure = RuntimeError.new('modern query failure')
    allow(adapter).to receive(:detail_levels_for).and_raise(failure)
    expect do
      wrapper.adapter_detail_levels_for(adapter:, kind: :init, context:, result:, mode: :sync)
    end.to(raise_error { |error| expect(error).to equal(failure) })
  end
end
