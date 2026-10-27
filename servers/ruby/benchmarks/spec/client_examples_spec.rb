# Run unbundled in the locked benchmark shell; optional generators are required.
# One shared mounted fixture excludes setup from the per-render measurements.
# rubocop:disable RSpec/InstanceVariable, RSpec/LeakyLocalVariable
require_relative '../performance_compare'
root = File.expand_path('../../../..', __dir__)
%w[servers/ruby clients/ruby clients/go clients/rust clients/typescript].each do |component|
  $:.unshift(File.join(root, component, 'lib'))
end
require 'haveapi'
require 'rack/mock'
require 'base64'
require 'cgi'
require_relative '../../test_support/all_client_performance_fixture'

RSpec.configure { |config| config.fail_if_no_examples = true }

RSpec.describe HaveAPI::ClientExample, '.render' do
  # Each mode has its own registry entry. New entries need reviewed expectations
  # and a real supported profile here, rather than silently missing measurement.
  profiles = {
    '0' => nil, '2' => nil, '3' => nil, '5' => nil, '6' => nil,
    'javascript-callback' => nil, 'javascript-async' => nil,
    'typescript-callback' => nil, 'typescript-async' => nil,
    'python-sync' => nil, 'python-async' => nil,
    'go' => :go, 'rust-async' => :rust, 'rust-blocking' => :rust,
    'typescript-generated' => :typescript
  }.freeze
  lanes = %i[init basic token oauth2 public protected failure].freeze
  let(:matrix) { profiles }

  before(:all) do
    @server = HaveAPI::AllClientPerformanceFixture.build(resources: 2)
    @profiles = @server.documentation_client_profiles(1)
    @description = description(@server, 'admin')
    @large_description = Marshal.load(Marshal.dump(@description))
    unrelated = @large_description.fetch(:resources).fetch('resource1')
    unrelated[:resources] = 128.times.to_h { |i| ["unrelated#{i}", Marshal.load(Marshal.dump(@description[:resources]['resource1']))] }
    @measurements = []
  end

  after(:all) do
    RSpec.configuration.reporter.message("ALL_CLIENT_PERFORMANCE #{JSON.generate(registry: profiles.keys.sort, lanes:, measurements: @measurements)}")
  end

  def headers(user)
    { 'HTTP_HOST' => 'example.test', 'HTTP_ACCEPT_LANGUAGE' => 'en',
      'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64("#{user}:fixture-only")}" }
  end

  def description(server, user)
    server.describe_version(HaveAPI::Context.new(server, version: 1,
                                                         user: HaveAPI::DocumentationPerformanceFixture::User.new(user), params: {}))
  end

  def context(description, profile, action_name: 'protected', sample_index: 0, resource_name: 'resource0')
    resource = description.fetch(:resources).fetch(resource_name)
    action = resource.fetch(:actions).fetch(action_name)
    HaveAPI::ClientExample::Context.new(version: 1, host: 'example.test',
                                        base_url: 'http://example.test/benchmark/api/',
                                        version_url: 'http://example.test/benchmark/api/v1/',
                                        description:, profile:, resource_path: [resource_name.to_s],
                                        resource:, action_name:, action:, sample: action.fetch(:examples).fetch(sample_index))
  end

  def render(client, lane, ctx)
    if %i[basic token oauth2].include?(lane)
      client.render(:auth, context: ctx, auth_method: lane, auth_description: ctx.description.fetch(:authentication).fetch(lane))
    else
      client.render(lane == :init ? :init : :example, context: ctx)
    end
  end

  def expect_result(result, id, lane)
    expect(result).to be_a(Hash), "#{id}/#{lane} returned no panel"
    if id == 'typescript-generated' && lane == :oauth2
      expect(result[:status]).to eq(:limitation)
      expect(result[:reason]).to be_a(String)
      expect(result[:reason]).not_to be_empty
    else
      expect(result[:status]).to eq(:code), "#{id}/#{lane}: #{result.inspect}"
      expect(result[:code]).to be_a(String)
      expect(result[:code]).not_to be_empty
      if %w[0 3].include?(id) && lane == :oauth2
        expect(result[:code]).to include('OAuth2 is not supported')
      end
    end
  end

  def allocations(count: 8, &block)
    2.times(&block)
    Array.new(3) do
      before = GC.stat(:total_allocated_objects)
      count.times(&block)
      (GC.stat(:total_allocated_objects) - before) / count.to_f
    end.min
  end

  def calls(&block)
    count = 0
    trace = TracePoint.new(:call) { count += 1 }
    trace.enable(&block)
    count
  ensure
    trace&.disable
  end

  it 'requires exactly the reviewed registry and all real profiles' do
    ids = described_class.clients.map(&:id)
    expect(ids.sort).to eq(profiles.keys.sort)
    expect(ids.uniq).to eq(ids)
    expect(@profiles.keys.sort).to eq(%i[go rust typescript])
    expect(@description.fetch(:authentication).keys.sort).to eq(%i[basic oauth2 token])
  end

  profiles.each do |id, language|
    lanes.each do |lane|
      it "bounds #{id}/#{lane} work and allocations with unrelated descendants" do
        client = described_class.clients.find { |item| item.id == id }
        expect(client).not_to be_nil
        profile = language && @profiles.fetch(language)
        options = { action_name: lane == :public ? 'public' : 'protected', sample_index: lane == :failure ? 1 : 0 }
        small = context(@description, profile, **options)
        large = context(@large_description, profile, **options)
        expect(client.available?(small)).to be(true)
        expect(client.available?(large)).to be(true)
        before = Marshal.dump([small.description, large.description])
        expected = render(client, lane, small)
        expect_result(expected, id, lane)
        expect(render(client, lane, large)).to eq(expected)
        small_calls = calls { render(client, lane, small) }
        large_calls = calls { render(client, lane, large) }
        small_allocations = allocations { render(client, lane, small) }
        large_allocations = allocations { render(client, lane, large) }
        @measurements << { id:, lane:, allocations: [small_allocations, large_allocations], calls: [small_calls, large_calls] }
        # Selected action/provider/sample is unchanged. Allow fixed VM/lookup
        # slack, while recursive walks of the 128 unrelated subtrees must fail.
        expect(large_calls).to be <= small_calls + 32
        expect(large_allocations).to be <= small_allocations + 32
        expect(Marshal.dump([small.description, large.description])).to eq(before)
      end
    end
  end

  def expect_panel(body, anchor, result)
    panel = body.match(%r{<div id="#{Regexp.escape(anchor)}">\s*(.*?)</div>}m)
    expect(panel).not_to be_nil, "Missing #{anchor}"
    text = result.fetch(result[:status] == :code ? :code : :reason)
    expect(panel[1]).to include(CGI.escapeHTML(text))
    expect(panel[1]).to include(result[:status] == :code ? '<pre><code' : 'client-limitation')
  end

  def expect_complete_page(server, user, resources)
    desc = description(server, user)
    response = Rack::MockRequest.new(server.app).get('/benchmark/api/v1/', **headers(user))
    expect(response.status).to eq(200)
    expect(response['content-type']).to start_with('text/html')
    expect(response.body).to include('PUBLIC_SAMPLE')
    %w[ADMIN_ONLY_ACTION ADMIN_ONLY_DEFAULT ADMIN_ONLY_REQUEST ADMIN_ONLY_RESPONSE ADMIN_ONLY_ACTION_SAMPLE admin_field admin_only].each do |marker|
      expect(response.body.include?(marker)).to eq(user == 'admin'), marker
    end
    example_count = 0
    HaveAPI::ClientExample.clients.each do |client|
      language = matrix.fetch(client.id)
      profile = language && server.documentation_client_profiles(1).fetch(language)
      ctx = context(desc, profile)
      expect(client.available?(ctx)).to be(true)
      expect_panel(response.body, "init-#{client.id}", render(client, :init, ctx))
      desc.fetch(:authentication).each_key do |method|
        result = render(client, method, ctx)
        expect_result(result, client.id, method)
        expect_panel(response.body, "auth-#{method}-#{client.id}", result)
      end
      resources.times do |index|
        resource_name = "resource#{index}"
        desc.fetch(:resources).fetch(resource_name).fetch(:actions).each do |action_name, action|
          action.fetch(:examples).each_index do |sample_index|
            selected = context(desc, profile, action_name: action_name.to_s, sample_index:, resource_name:)
            result = client.render(:example, context: selected)
            expect_result(result, client.id, :example)
            expect_panel(response.body, "example-#{resource_name}-#{action_name}-#{sample_index}-#{client.id}", result)
            example_count += 1
          end
        end
      end
    end
    expected_samples = (resources * 2 * (user == 'admin' ? 3 : 2)) + (user == 'admin' ? 1 : 0)
    expect(example_count).to eq(expected_samples * matrix.length)
    response
  end

  it 'renders every real panel and isolates admin/member/admin pages through the same adapters' do
    first = expect_complete_page(@server, 'admin', 2)
    expect_complete_page(@server, 'member', 2)
    last = expect_complete_page(@server, 'admin', 2)
    expect(last.body).to eq(first.body)
  end

  it 'bounds complete all-profile page allocations by linear output growth' do
    measurements = [2, 4, 8].map do |resources|
      server = HaveAPI::AllClientPerformanceFixture.build(resources:)
      response = expect_complete_page(server, 'admin', resources)
      request = Rack::MockRequest.new(server.app)
      allocated = allocations(count: 1) { request.get('/benchmark/api/v1/', **headers('admin')) }
      { resources:, bytes: response.body.bytesize, allocations: allocated }
    end
    @measurements << { pages: measurements }
    small, medium, large = measurements
    expect(large[:bytes]).to be > medium[:bytes]
    expect(medium[:bytes]).to be > small[:bytes]
    expect(medium[:allocations]).to be > small[:allocations]
    # Doubling the added resources doubles actual panels/output. A 2.5x
    # incremental allowance covers bookkeeping; quadratic copying approaches 4x.
    expect(large[:allocations] - medium[:allocations]).to be <= 2.5 * (medium[:allocations] - small[:allocations])
  end
end
# rubocop:enable RSpec/InstanceVariable, RSpec/LeakyLocalVariable
