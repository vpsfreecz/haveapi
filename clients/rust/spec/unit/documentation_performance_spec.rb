require 'spec_helper'
require 'haveapi/rust_client/documentation'

describe HaveAPI::RustClient::Documentation do
  include RustGeneratorFixtures

  let(:schema) do
    result = snapshot
    result['description']['authentication'] = { 'token' => { 'http_header' => 'X-Token' } }
    result
  end
  let(:adapter) { described_class.from_snapshot(snapshot: schema, crate_name: 'fixture-client', crate_version: '0.1.0') }
  let(:normalized_nodes) { [] }
  let(:context_type) { Struct.new(:version, :base_url, :description, :resource_path, :action_name, :sample, :detail) }
  let(:context) do
    context_type.new(detail: :thorough, version: '1.0', base_url: 'https://example.test/', resource_path: ['widget'], action_name: 'update',
                     sample: { path_params: [1], request: { name: 'widget' }, response: { id: 1 }, status: true })
  end

  def description_with_unrelated_descendants(size)
    description = Marshal.load(Marshal.dump(schema['description']))
    # Keep ancestor map width fixed: only unrelated descendants grow.
    unrelated = {
      'resources' => size.times.to_h do |index|
        ["resource#{index}", { 'actions' => { 'ignored' => action },
                               'resources' => { 'nested' => { 'description' => ['unused'] * size } } }]
      end
    }
    description['resources']['unrelated'] = unrelated
    description['resources']['widget']['actions']['unrelated'] = unrelated
    description['authentication']['unrelated'] = unrelated
    description['authentication']['token']['resources'] = unrelated
    description
  end

  def render_with_work(description, mode, **options)
    context.description = description
    normalized_nodes.clear
    result = adapter.render(context:, mode:, **options)
    [result, normalized_nodes.length]
  end

  before do
    allow(adapter).to receive(:normalize).and_wrap_original do |original, value|
      # Every recursive call crosses this wrapper, including scalar leaves.
      normalized_nodes << value.object_id
      original.call(value)
    end
  end

  %i[async blocking].each do |mode|
    it "bounds #{mode} action and credential normalization by the selected subtree" do
      small = render_with_work(description_with_unrelated_descendants(1), mode, kind: :example)
      large = render_with_work(description_with_unrelated_descendants(64), mode, kind: :example)
      expect(small.first[:status]).to eq(:code)
      expect(small.first[:code]).to include('.token(')
      expect(large.first).to eq(small.first)
      expect(small.last).to be > 10
      expect(large.last).to eq(small.last)
    end

    it "bounds #{mode} authentication normalization while retaining complete selected-provider equality" do
      descriptions = [1, 64].map do |size|
        description = description_with_unrelated_descendants(size)
        description['authentication']['token']['resources'] = { 'login' => { 'description' => ['advertised'] } }
        description
      end
      results = descriptions.map do |description|
        render_with_work(description, mode, kind: :auth, auth_method: :token,
                                            auth_description: { http_header: 'X-Token',
                                                                resources: { login: { description: ['advertised'] } } })
      end
      expect(results.first.first[:status]).to eq(:code)
      expect(results.last.first).to eq(results.first.first)
      expect(results.first.last).to be > 10
      expect(results.last.last).to eq(results.first.last)
    end

    it "bounds #{mode} unavailable provider lookups without retaining hidden provider data" do
      descriptions = [1, 64].map { |size| description_with_unrelated_descendants(size) }
      %i[unknown token].each do |provider|
        descriptions.each { |description| description['authentication'].delete('token') } if provider == :token
        small, large = descriptions.map do |description|
          render_with_work(description, mode, kind: :auth, auth_method: provider, auth_description: {})
        end
        expect(small.first).to eq(status: :limitation,
                                  reason: 'This authentication provider is unavailable in the authorized Rust API client profile.')
        expect(large).to eq(small)
      end
    end

    it "preserves #{mode} limitations without normalizing unrelated descendants" do
      descriptions = [1, 64].map { |size| description_with_unrelated_descendants(size) }
      descriptions.each { |description| description['resources']['widget']['actions']['update']['input']['parameters']['name']['type'] = 'Integer' }
      small, large = descriptions.map { |description| render_with_work(description, mode, kind: :example) }
      expect(small.first[:status]).to eq(:limitation)
      expect(large).to eq(small)
      descriptions.each { |description| description['resources']['widget']['actions'].delete('update') }
      small, large = descriptions.map { |description| render_with_work(description, mode, kind: :example) }
      expect(small.first[:status]).to eq(:limitation)
      expect(large).to eq(small)
    end
  end
end
