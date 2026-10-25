require 'spec_helper'
require_relative '../../test_support/performance_endpoint_fixture'

RSpec.describe HaveAPI::PerformanceFixtures::Endpoints, '.build' do
  def run_list(rows)
    scenario = described_class.build(id: 'api.list', dimensions: { rows: })
    scenario.reset!(iterations: 2)
    responses = Array.new(2) { scenario.call }
    identities = responses.each_with_index.map { |response, index| scenario.validate!(response, index:) }
    [identities, scenario.counters]
  ensure
    scenario&.close
  end

  def allocated_per_request(rows)
    scenario = described_class.build(id: 'api.list', dimensions: { rows: })
    2.times do
      scenario.reset!(iterations: 10)
      10.times { scenario.call }
    end
    Array.new(3) do
      scenario.reset!(iterations: 10)
      responses = Array.new(10)
      GC.start
      allocated = GC.stat(:total_allocated_objects)
      index = 0
      while index < responses.length
        responses[index] = scenario.call
        index += 1
      end
      delta = GC.stat(:total_allocated_objects) - allocated
      responses.each_with_index { |response, operation| scenario.validate!(response, index: operation) }
      scenario.counters
      delta / 10.0
    end.min
  ensure
    scenario&.close
  end

  it 'serializes complete ordered lists at sizes 1, 32 and 128 with fixed action work' do
    bytes = [1, 32, 128].map do |rows|
      identities, counters = run_list(rows)
      expect(identities.first).to eq(identities.last)
      output = identities.first[:canonical_body].fetch('response').fetch('probe')
      expect(output.length).to eq(rows)
      expect(output.map { |row| row.fetch('id') }).to eq((1..rows).to_a)
      expect(output.last.fetch('label')).to eq("item-#{rows}")
      output.each { |row| expect(row).not_to have_key('secret') }
      expect(counters[:operations]).to eq(Array.new(2) { { queries: 0, authorizations: 1, executions: 1 } })
      identities.first[:body_bytes]
    end
    expect(bytes.each_cons(2)).to all(satisfy { |small, large| small < large })
  end

  it 'keeps output and counters independent across reset batch sizes' do
    scenario = described_class.build(id: 'api.list', dimensions: { rows: 32 })
    scenario.reset!(iterations: 1)
    first = scenario.validate!(scenario.call, index: 0)
    records = scenario.counters[:operations]
    scenario.reset!(iterations: 3)
    responses = Array.new(3) { scenario.call }
    responses.each_with_index do |response, index|
      expect(scenario.validate!(response, index:)).to eq(first)
    end
    expect(scenario.counters[:operations].length).to eq(3)
    expect(scenario.counters[:operations].first).not_to equal(records.first)
    expect(scenario.counters[:operations].map(&:object_id).uniq.length).to eq(3)
  ensure
    scenario&.close
  end

  it 'bounds allocation growth by serialized rows rather than their square' do
    small, medium, large = [1, 32, 128].map { |rows| allocated_per_request(rows) }

    # Reference Ruby 3.4.11: 640/795/1275 objects per request. Output work
    # grows with rows; the 96-row increment has a 4x allowance relative to
    # the 31-row increment, plus 32 objects of fixed VM bookkeeping slack.
    expect(medium).to be >= small
    expect(large).to be > medium
    expect(large - medium).to be <= (4 * (medium - small)) + 32
  end
end
