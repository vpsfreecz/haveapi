require 'spec_helper'
require_relative '../../benchmarks/endpoints'
require_relative '../../benchmarks/documentation'
require_relative '../../test_support/documentation_performance_fixture'

describe HaveAPI::Performance::DocumentationScenario do
  let(:scenario) { described_class.new(id: 'docs.html_resources', dimensions: { size: 2, user: 'admin' }) }
  let(:overview) do
    scenario.reset!(iterations: 1)
    scenario.call
  end
  let(:error) { HaveAPI::Performance::ContractError }

  def response_with(body)
    Rack::MockResponse.new(200, { 'content-type' => 'text/html' }, body)
  end

  def replace_map(body)
    body.sub(%r{(<script\b[^>]*data-legacy-anchors[^>]*>)(.*?)(</script>)}m) do
      before, json, after = Regexp.last_match.captures
      values = JSON.parse(json)
      yield(values)
      "#{before}#{JSON.generate(values)}#{after}"
    end
  end

  it 'accepts the actual overview and preserves authorization counters and raw identity' do
    identity = scenario.validate!(overview, index: 0)
    expect(identity[:page]).to include(shape: 'overview', actual_examples: 0, resources: 2, actions: 3)
    expect(identity[:body_sha256]).to eq(Digest::SHA256.hexdigest(overview.body))
    expect(overview.body).not_to include('PUBLIC_SAMPLE_', 'ADMIN_ONLY_REQUEST')
  end

  it 'accepts the strict legacy full-page contract without accepting an empty third shape' do
    legacy = response_with('init-python-sync init-examples PUBLIC_SAMPLE_0 ADMIN_ONLY_REQUEST')
    expect(scenario.validate_body!(legacy)[:page]).to include(shape: 'monolithic')
    expect { scenario.validate_body!(response_with('<h1>Empty</h1>')) }.to raise_error(error, /panels/)
  end

  it 'requires directory navigation, canonical targets and real initialization code' do
    bodies = [
      overview.body.gsub('data-resource-directory-link', 'data-missing-directory-link'),
      overview.body.sub('href="/benchmark/api/v1/?page=resources"', 'href="https://foreign.example/"'),
      overview.body.sub('id="init-python-sync"', 'id="missing-python-sync"'),
      overview.body.sub('id="init-python-sync-thorough"', 'id="missing-python-thorough"'),
      overview.body.sub('id="init-javascript-async"', 'id="missing-javascript-async"')
    ]
    bodies.each do |body|
      expect { scenario.validate_body!(response_with(body)) }.to raise_error(error, /navigation|initialization/)
    end
  end

  it 'rejects duplicate, malformed, wrong and mixed overview representations' do
    bodies = [
      overview.body.sub('data-page="overview"', 'data-page="resource"'),
      overview.body.sub('data-docs data-page=', 'data-docs data-docs data-page='),
      "#{overview.body}<div data-docs data-page=\"overview\"></div>",
      overview.body.sub('data-page="overview"', 'data-page="overview" data-page="resource"'),
      "#{overview.body}<div id=\"example-resource0-action0-0-examples\">PUBLIC_SAMPLE_0</div>"
    ]
    bodies.each { |body| expect { scenario.validate_body!(response_with(body)) }.to raise_error(error, /overview/) }
  end

  it 'rejects missing, wrong or foreign legacy destinations and wrong authorization roles' do
    maps = [
      ->(values) { values.delete('root-resource1-action0') },
      ->(values) { values['root-resource1'] = '/benchmark/api/v1/?resource=resource0' },
      ->(values) { values['example-resource0-action0-'] = 'https://foreign.example/' },
      ->(values) { values.delete('root-resource0-admin_only') },
      ->(values) { values['auth-basic'] = 'https://foreign.example/' }
    ]
    maps.each do |mutate|
      body = replace_map(overview.body, &mutate)
      expect { scenario.validate_body!(response_with(body)) }.to raise_error(error, /authorization|targets/)
    end
    member = described_class.new(id: 'docs.html_resources', dimensions: { size: 2, user: 'member' })
    expect { member.validate_body!(overview) }.to raise_error(error, /authorization/)
  end

  it 'rejects malformed legacy JSON and private parameter or sample data in either role' do
    body = overview.body.sub(%r{(<script[^>]*data-legacy-anchors[^>]*>).*?(</script>)}m, '\1[\2')
    expect { scenario.validate_body!(response_with(body)) }.to raise_error(error, /map/)
    %w[PUBLIC_SAMPLE_0 ADMIN_ONLY_DEFAULT ADMIN_ONLY_REQUEST ADMIN_ONLY_RESPONSE admin_field].each do |marker|
      expect { scenario.validate_body!(response_with("#{overview.body}<p>#{marker}</p>")) }.to raise_error(error, /action data/)
    end
  end

  it 'retains the optional benchmark root HTML lane for both explicit representations' do
    benchmark = HaveAPI::DocumentationBenchmark.new([])
    dimensions = { resource_count: 2 }
    expect(benchmark.send(:html_output, overview, dimensions)[:status]).to eq(200)
    legacy = response_with('init-examples PUBLIC_SAMPLE_0')
    expect(benchmark.send(:html_output, legacy, dimensions)[:status]).to eq(200)
    malformed = response_with(overview.body.sub('data-page="overview"', 'data-page="resource"'))
    expect { benchmark.send(:html_output, malformed, dimensions) }.to raise_error(HaveAPI::DocumentationBenchmark::InvalidOutput)
  end
end
