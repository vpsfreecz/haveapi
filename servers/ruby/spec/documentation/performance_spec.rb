require 'spec_helper'
require 'base64'
require_relative '../../test_support/documentation_performance_fixture'

describe HaveAPI::Server, '#mount' do
  let(:server) do
    HaveAPI::DocumentationPerformanceFixture.build(resource_count: 3, actions_per_resource: 2)
  end
  let(:contexts) { [] }
  let(:help_inputs) { [] }
  let(:resource_derivations) { [] }

  around do |example|
    trace = TracePoint.new(:call) do |call|
      next unless call.defined_class == HaveAPI::ClientExample::Context && call.method_id == :normalize
      next unless call.binding.local_variable_get(:field) == :resource

      value = call.binding.local_variable_get(:value)
      resource_derivations << value if value
    end
    trace.enable { example.run }
  ensure
    trace&.disable
  end

  before do
    HaveAPI::ClientExample.clients.each do |client|
      allow(client).to receive(:render).and_wrap_original do |original, kind, context:, **arguments|
        contexts << context
        original.call(kind, context:, **arguments)
      end
    end
    allow(server).to receive(:describe_version).and_wrap_original do |original, *arguments|
      original.call(*arguments).tap do |help|
        help_inputs << [help, Marshal.dump(help)]
      end
    end
  end

  def request_as(user)
    contexts.clear
    resource_derivations.clear
    Rack::MockRequest.new(server.app).get(
      '/benchmark/api/v1/?resource=resource0', 'HTTP_HOST' => 'example.test',
                                               'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64("#{user}:fixture-only")}"
    )
  end

  def expect_shared_request(response)
    expect(response.status).to eq(200)
    expect(response.body).to include('PUBLIC_SAMPLE_0', 'example-resource0-action0-0',
                                     'data-client="javascript-callback"', 'data-client="javascript-async"',
                                     'data-client="typescript-callback"', 'data-client="typescript-async"',
                                     'data-client="python-sync"', 'data-client="python-async"')
    expect(response.body).not_to include('id="example-resource1-', 'id="example-resource2-', 'init-examples')
    expect(contexts.length).to be > 20
    expect(contexts.map(&:resource_path).uniq).to eq([['resource0']])
    expect(contexts.map { |context| context.resource.__id__ }.uniq.length).to eq(1)
    expect(resource_derivations.length).to eq(1)
    description = contexts.first.description
    contexts.each { |context| expect(context.description).to equal(description) }
    expect(description).to be_frozen
    description
  end

  it 'shares one description across real panels and isolates sequential admin/member/admin requests' do
    first_admin = request_as('admin')
    admin_description = expect_shared_request(first_admin)
    privileged_markers = %w[ADMIN_ONLY_ACTION ADMIN_ONLY_DEFAULT ADMIN_ONLY_REQUEST ADMIN_ONLY_RESPONSE
                            ADMIN_ONLY_ACTION_SAMPLE admin_field admin_only]
    privileged_markers.each { |marker| expect(first_admin.body).to include(marker) }

    member = request_as('member')
    member_description = expect_shared_request(member)
    expect(member_description).not_to equal(admin_description)
    privileged_markers.each { |marker| expect(member.body).not_to include(marker) }
    expect(JSON.generate(contexts.map { |context| [context.description, context.action, context.sample] }))
      .not_to match(/ADMIN_ONLY_|admin_field|admin_only/)
    expect(member_description[:resources]['resource0'][:actions]).not_to have_key('admin_only')
    selected = contexts.find { |context| context.action_name == 'action0' }
    expect(selected.action[:input][:parameters]).not_to have_key(:admin_field)
    expect(selected.sample[:request]).to include(enabled: false, count: 0, nullable: nil, value0: '')

    last_admin = request_as('admin')
    restored_description = expect_shared_request(last_admin)
    expect(restored_description).not_to equal(admin_description)
    expect(restored_description).not_to equal(member_description)
    expect(restored_description).to eq(admin_description)
    privileged_markers.each { |marker| expect(last_admin.body).to include(marker) }

    help_inputs.each do |help, original|
      expect(Marshal.dump(help)).to eq(original)
      expect(help).not_to be_frozen
      expect(help[:resources]).not_to be_frozen
      expect(help[:resources]['resource0'][:actions]['action0'][:examples].first[:request]).not_to be_frozen
    end
  end

  it 'does not alias distinct raw resources at the same canonical path' do
    helper = Object.new
    helper.extend(HaveAPI::Server::ServerHelpers)
    parent = HaveAPI::ClientExample::Context.new(version: 1, host: 'example.test',
                                                 base_url: 'http://example.test/', version_url: 'http://example.test/v1/',
                                                 description: {})
    helper.instance_variable_set(:@documentation_context, parent)
    first = { actions: { 'show' => { description: 'first' } }, resources: {} }
    second = { actions: { 'show' => { description: 'second' } }, resources: {} }
    before = Marshal.dump([first, second])
    a = helper.documentation_context(resource_path: [:widget], resource: first)
    b = helper.documentation_context(resource_path: ['widget'], resource: first, detail: :thorough)
    c = helper.documentation_context(resource_path: ['widget'], resource: second)
    expect(a.resource).to equal(b.resource)
    expect(a.resource).not_to equal(c.resource)
    expect(a.resource).not_to equal(first)
    expect(a.description).to equal(c.description)
    expect(a.resource[:actions]['show'][:description]).to eq('first')
    expect(c.resource[:actions]['show'][:description]).to eq('second')
    expect(Marshal.dump([first, second])).to eq(before)
  end
end
