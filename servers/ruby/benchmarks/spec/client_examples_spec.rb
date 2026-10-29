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
  details = %i[simple thorough].freeze
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
    RSpec.configuration.reporter.message("ALL_CLIENT_PERFORMANCE #{JSON.generate(registry: profiles.keys.sort, lanes:, details:, measurements: @measurements)}")
  end

  def headers(server, user)
    { 'HTTP_HOST' => 'example.test', 'HTTP_ACCEPT_LANGUAGE' => 'en',
      'HTTP_COOKIE' => server.fixture_documentation_cookie(user) }
  end

  def description(server, user)
    server.describe_version(HaveAPI::Context.new(server, version: 1,
                                                         user: HaveAPI::DocumentationPerformanceFixture::User.new(user), params: {}))
  end

  def context(description, profile, action_name: 'protected', sample_index: 0, resource_name: 'resource0', detail: :simple, origin: 'http://example.test')
    resource = description.fetch(:resources).fetch(resource_name)
    action = resource.fetch(:actions).fetch(action_name)
    HaveAPI::ClientExample::Context.new(version: 1, host: 'example.test',
                                        base_url: "#{origin}/benchmark/api/",
                                        version_url: "#{origin}/benchmark/api/v1/",
                                        description:, profile:, detail:, resource_path: [resource_name.to_s],
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
    lanes.product(details).each do |lane, detail|
      it "bounds #{id}/#{lane}/#{detail} work and allocations with unrelated descendants" do
        client = described_class.clients.find { |item| item.id == id }
        expect(client).not_to be_nil
        profile = language && @profiles.fetch(language)
        options = { action_name: lane == :public ? 'public' : 'protected', sample_index: lane == :failure ? 1 : 0, detail: }
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
        @measurements << { id:, lane:, detail:, allocations: [small_allocations, large_allocations], calls: [small_calls, large_calls] }
        # Selected action/provider/sample is unchanged. Allow fixed VM/lookup
        # slack, while recursive walks of the 128 unrelated subtrees must fail.
        expect(large_calls).to be <= small_calls + 32
        expect(large_allocations).to be <= small_allocations + 32
        expect(Marshal.dump([small.description, large.description])).to eq(before)
      end
    end
  end

  def expect_panel(body, anchor, result)
    panel = body.match(%r{<details\b[^>]*\bdata-example-panel\b[^>]*\bid="#{Regexp.escape(anchor)}"[^>]*>(.*?)</details>}m)
    expect(panel).not_to be_nil, "Missing #{anchor}"
    text = result.fetch(result[:status] == :code ? :code : :reason)
    expect(panel[1]).to include(CGI.escapeHTML(text))
    expect(panel[1]).to include(result[:status] == :code ? '<pre><code' : 'client-limitation')
  end

  def expect_meaningful_group(body, base, client, kind, ctx, auth_method: nil, auth_description: nil)
    simple = client.render(kind, context: ctx, auth_method:, auth_description:)
    expect(simple).not_to be_nil
    levels = client.detail_levels_for(kind, context: ctx, result: simple, auth_method:, auth_description:)
    group = body.match(%r{<div class="docs-example" data-example data-example-details="([^"]*)" id="#{Regexp.escape(base)}-examples">(.*?)</div>}m)
    expect(group).not_to be_nil, base
    declared = JSON.parse(CGI.unescapeHTML(group[1]))
    expect(declared.fetch(client.id)).to eq(levels.map(&:to_s))
    actual = group[2].scan(/data-example-panel[^>]*data-client="#{Regexp.escape(client.id)}"[^>]*data-detail="([^"]+)"/).flatten
    expect(actual).to eq(levels.map(&:to_s))
    levels.each do |detail|
      result = detail == :simple ? simple : client.render(kind, context: ctx.with(detail:), auth_method:, auth_description:)
      expect_result(result, client.id, kind == :auth ? auth_method : kind)
      expect_panel(body, "#{base}-#{client.id}#{'-thorough' if detail == :thorough}", result)
    end
    return unless levels == [:simple]

    expect(body).to include("id=\"#{base}-#{client.id}-thorough\"")
  end

  def request_page(server, user, query = '')
    response = Rack::MockRequest.new(server.app).get("#{server.fixture_documentation_oauth.origin}/benchmark/api/v1/#{query}", **headers(server, user))
    expect(response.status).to eq(200)
    expect(response['content-type']).to start_with('text/html')
    response.body
  end

  def expect_complete_page(server, user, resources, actions: 2)
    desc = description(server, user)
    overview = request_page(server, user)
    authentication = request_page(server, user, '?page=authentication')
    directory = request_page(server, user, '?page=resources')
    links = directory.scan(/data-resource-link="([^"]*)"/).flatten
    expect(links.sort).to eq(resources.times.map { |index| "resource#{index}" }.sort)
    expect(directory).not_to include('PUBLIC_SAMPLE', 'ADMIN_ONLY_REQUEST', 'ADMIN_ONLY_RESPONSE', 'id="example-')
    expect(overview).to include('data-resource-directory-link')
    expect(overview).not_to include('data-resource-link=')
    pages = resources.times.to_h do |index|
      name = "resource#{index}"
      [name, request_page(server, user, "?resource=#{name}")]
    end
    expect(overview).not_to include('id="example-')
    expect(overview).not_to include('PUBLIC_SAMPLE', 'ADMIN_ONLY_REQUEST', 'ADMIN_ONLY_RESPONSE')
    pages.each do |name, body|
      expect(body).to include('PUBLIC_SAMPLE')
      expect(body).not_to include('id="init-examples"')
      pages.each_key do |other|
        next if other == name

        expect(body).not_to include("id=\"example-#{other}-")
      end
    end
    combined = [overview, authentication, directory, *pages.values].join
    %w[ADMIN_ONLY_ACTION ADMIN_ONLY_DEFAULT ADMIN_ONLY_REQUEST ADMIN_ONLY_RESPONSE ADMIN_ONLY_ACTION_SAMPLE admin_field admin_only].each do |marker|
      expect(combined.include?(marker)).to eq(user == 'admin'), marker
    end
    example_count = 0
    HaveAPI::ClientExample.clients.each do |client|
      language = matrix.fetch(client.id)
      profile = language && server.documentation_client_profiles(1).fetch(language)
      ctx = context(desc, profile, origin: server.fixture_documentation_oauth.origin)
      expect(client.available?(ctx)).to be(true)
      expect_meaningful_group(overview, 'init', client, :init, ctx)
      desc.fetch(:authentication).each do |method, auth|
        expect_meaningful_group(authentication, "auth-#{method}", client, :auth, ctx, auth_method: method, auth_description: auth)
      end
      pages.each do |resource_name, body|
        desc.fetch(:resources).fetch(resource_name).fetch(:actions).each do |action_name, action|
          action.fetch(:examples).each_index do |sample_index|
            selected = context(desc, profile, action_name: action_name.to_s, sample_index:, resource_name:,
                                              origin: server.fixture_documentation_oauth.origin)
            expect_meaningful_group(body, "example-#{resource_name}-#{action_name}-#{sample_index}", client, :example, selected)
            example_count += 1
          end
        end
      end
    end
    expected_samples = (resources * actions * (user == 'admin' ? 3 : 2)) + (user == 'admin' ? 1 : 0)
    expect(example_count).to eq(expected_samples * matrix.length)
    combined
  end

  it 'renders every real panel and isolates admin/member/admin pages through the same adapters' do
    first = expect_complete_page(@server, 'admin', 2)
    expect_complete_page(@server, 'member', 2)
    last = expect_complete_page(@server, 'admin', 2)
    expect(last).to eq(first)
  end

  it 'bounds complete all-profile page allocations by linear output growth' do
    measurements = [2, 4, 8].map do |resources|
      server = HaveAPI::AllClientPerformanceFixture.build(resources:)
      correctness = expect_complete_page(server, 'admin', resources)
      request = Rack::MockRequest.new(server.app)
      # Measure the four page kinds with one selected resource. Correctness
      # above still checks every resource and both details; adding unrelated
      # resources must grow navigation, not action rendering on the selected page.
      paths = ['', '?page=authentication', '?page=resources', '?resource=resource0']
      bytes = paths.sum { |query| request.get("#{server.fixture_documentation_oauth.origin}/benchmark/api/v1/#{query}", **headers(server, 'admin')).body.bytesize }
      allocated = allocations(count: 1) do
        paths.each { |query| request.get("#{server.fixture_documentation_oauth.origin}/benchmark/api/v1/#{query}", **headers(server, 'admin')) }
      end
      { resources:, bytes:, correctness_bytes: correctness.bytesize, allocations: allocated }
    end
    @measurements << { pages: measurements }
    small, medium, large = measurements
    expect(large[:bytes]).to be > medium[:bytes]
    expect(medium[:bytes]).to be > small[:bytes]
    expect(medium[:allocations]).to be > small[:allocations]
    # The same page kinds retain their panel count; added resources grow only
    # authorized descriptions/navigation. Keep the existing 2.5x growth budget.
    expect(large[:allocations] - medium[:allocations]).to be <= 2.5 * (medium[:allocations] - small[:allocations])
  end

  it 'bounds one resource page allocations as its own action panels grow' do
    measurements = [2, 4, 8].map do |actions|
      server = HaveAPI::AllClientPerformanceFixture.build(resources: 1, actions:)
      expect_complete_page(server, 'admin', 1, actions:)
      request = Rack::MockRequest.new(server.app)
      response = request.get("#{server.fixture_documentation_oauth.origin}/benchmark/api/v1/?resource=resource0", **headers(server, 'admin'))
      allocated = allocations(count: 1) do
        request.get("#{server.fixture_documentation_oauth.origin}/benchmark/api/v1/?resource=resource0", **headers(server, 'admin'))
      end
      { actions:, bytes: response.body.bytesize, allocations: allocated }
    end
    @measurements << { action_pages: measurements }
    small, medium, large = measurements
    expect(large[:bytes]).to be > medium[:bytes]
    expect(medium[:bytes]).to be > small[:bytes]
    expect(medium[:allocations]).to be > small[:allocations]
    # Both selected panels and description grow here. Repeated whole-description
    # copying per panel approaches quadratic growth and violates the same budget.
    expect(large[:allocations] - medium[:allocations]).to be <= 2.5 * (medium[:allocations] - small[:allocations])
  end
end
# rubocop:enable RSpec/InstanceVariable, RSpec/LeakyLocalVariable
