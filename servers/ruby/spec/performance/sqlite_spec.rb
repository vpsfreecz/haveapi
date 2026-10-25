require 'spec_helper'
require_relative '../../test_support/performance_sqlite_fixture'
require_relative '../../benchmarks/endpoints'

describe HaveAPI::PerformanceFixtures::SQLite do
  def with_scenario(id: 'sqlite.includes', **dimensions)
    scenario = described_class.build(id:, dimensions:)
    yield scenario
  ensure
    scenario&.close
  end

  def run_operations(scenario, count = 2)
    scenario.reset!(iterations: count)
    responses = Array.new(count) { scenario.call }
    responses.each_with_index { |response, index| scenario.validate!(response, index:) }
    [responses, scenario.counters.fetch(:operations)]
  end

  it 'reuses only SQLite body semantics while checking every query, authorization and called index' do
    with_scenario(rows: 32, include_depth: 2, user: 'member') do |scenario|
      allow(scenario).to receive(:validate_body!).and_call_original
      worker = HaveAPI::Performance::Worker.new({})
      result = worker.measure(scenario, 4)
      expect(result[:bodies].length).to eq(1)
      expect(scenario).to have_received(:validate_body!).once
      %i[queries authorizations executions].each do |counter|
        calls = 0
        allow(scenario).to receive(:call).and_wrap_original do |call|
          response = call.call
          calls += 1
          scenario.instance_variable_get(:@operations)[1][counter] += 1 if calls == 2
          response
        end
        expect { worker.measure(scenario, 3) }.to raise_error(/operation counters/)
      end
      scenario.reset!(iterations: 2)
      response = scenario.call
      expect { scenario.validate!(response, index: 1) { raise 'body validator must not run' } }.to raise_error(ArgumentError, /uncalled/)
    end
  end

  it 'exposes unique stable quick/weekly cases and rejects unsupported shapes' do
    quick = described_class.cases
    expect(quick).to eq([{ id: 'sqlite.page', dimensions: { rows: 128, page_size: 32 } },
                         { id: 'sqlite.includes', dimensions: { rows: 32, include_depth: 2 } }])
    weekly = described_class.cases(profile: 'weekly')
    expect(weekly.uniq).to eq(weekly)
    expect(weekly).to include(id: 'sqlite.includes', dimensions: { rows: 1024, include_depth: 2, user: 'member' })
    expect { described_class.cases(profile: 'missing') }.to raise_error(ArgumentError)
    expect { described_class.build(id: 'missing', dimensions: { rows: 1 }) }.to raise_error(ArgumentError)
    expect { described_class.build(id: 'sqlite.page', dimensions: { rows: 1024, page_size: 1024 }) }.to raise_error(ArgumentError)
  end

  [32, 128, 1024].each do |rows|
    it "keeps a fixed 32-row page at one real uncached query over #{rows} rows" do
      with_scenario(id: 'sqlite.page', rows:, page_size: 32) do |scenario|
        responses, counts = run_operations(scenario)
        expect(counts).to eq(Array.new(2) { { queries: 1, authorizations: 1, executions: 1 } })
        values = JSON.parse(responses.first.body).fetch('response').fetch('items')
        expect(values.map { |item| item.fetch('id') }).to eq((1..32).to_a)
        expect(values.first).to include('label' => '', 'enabled' => false, 'count' => 0, 'note' => nil)
      end
    end
  end

  [1, 32, 128].product([1, 2]).each do |rows, depth|
    it "bounds explicit depth #{depth} includes to #{depth + 1} queries for #{rows} rows while retaining row authorization" do
      with_scenario(rows:, include_depth: depth) do |scenario|
        responses, counts = run_operations(scenario)
        expected = { queries: depth + 1, authorizations: 1 + (rows * depth), executions: 1 }
        expect(counts).to eq([expected, expected])
        groups = JSON.parse(responses.first.body).fetch('response').fetch('items').map { |item| item.fetch('group') }
        expect(groups).to all(include('_meta' => include('resolved' => true)))
        expect(groups.first).to have_key('account') if depth == 2
        expect(groups.first).not_to have_key('account') if depth == 1
      end
    end
  end

  it 'applies the real ascending cursor before the fixed page limit' do
    with_scenario(id: 'sqlite.page', rows: 128, page_size: 32) do |scenario|
      path = scenario.instance_variable_get(:@path)
      scenario.instance_variable_set(:@path, path.sub('from_id%5D=0', 'from_id%5D=32'))
      response = scenario.call
      expect(response.status).to eq(200)
      body = JSON.parse(response.body)
      expect(body.fetch('status')).to be(true)
      expect(body.fetch('response').fetch('items').map { |item| item.fetch('id') }).to eq((33..64).to_a)
      expect(scenario.counters.fetch(:operations)).to eq([{ queries: 1, authorizations: 1, executions: 1 }])
    end
  end

  it 'keeps fixed-page allocation work independent of unreturned table rows' do
    allocations = [32, 1024].map do |rows|
      with_scenario(id: 'sqlite.page', rows:, page_size: 32) do |scenario|
        2.times { run_operations(scenario, 1) }
        3.times.map do
          scenario.reset!(iterations: 3)
          responses = Array.new(3)
          GC.start
          before = GC.stat(:total_allocated_objects)
          3.times { |index| responses[index] = scenario.call }
          count = GC.stat(:total_allocated_objects) - before
          responses.each_with_index { |response, index| scenario.validate!(response, index:) }
          count
        end.min
      end
    end
    # Ruby 3.4.11 calibration observed 2620 objects/request at every table size.
    # Fixed slack accommodates VM bookkeeping while rejecting table-sized work.
    expect(allocations.last - allocations.first).to be <= (128 * 3)
  end

  it 'serializes 1024 rows without passing an invalid pagination limit' do
    with_scenario(rows: 1024, include_depth: 2) do |scenario|
      responses, counts = run_operations(scenario, 1)
      expect(JSON.parse(responses.first.body).fetch('response').fetch('items').length).to eq(1024)
      expect(counts).to eq([{ queries: 3, authorizations: 2049, executions: 1 }])
    end
  end

  it 'keeps member association decisions and hidden values isolated between administrator requests' do
    with_scenario(rows: 32, include_depth: 2, user: 'admin') do |admin|
      with_scenario(rows: 32, include_depth: 2, user: 'member') do |member|
        first, = run_operations(admin, 1)
        restricted, counts = run_operations(member, 1)
        restored, = run_operations(admin, 1)
        expect(restored.first.body).to eq(first.first.body)
        expect(first.first.body).to include('GROUP_SECRET_2', 'ACCOUNT_SECRET_3')
        expect(restricted.first.body).not_to include('GROUP_SECRET', 'ACCOUNT_SECRET', '"label":"group2"', '"label":"account3"')
        items = JSON.parse(restricted.first.body).fetch('response').fetch('items')
        denied = { '_meta' => { 'resolved' => false, 'authorized' => false } }
        expect(items[1].fetch('group')).to eq(denied)
        expect(items[2].fetch('group').fetch('account')).to eq(denied)
        expect(counts).to eq([{ queries: 3, authorizations: 49, executions: 1 }])
      end
    end
  end

  it 'rechecks administrator/member permissions on one app and pool across repeated requests' do
    with_scenario(rows: 32, include_depth: 2) do |scenario|
      results = %w[admin member admin].map do |user|
        scenario.instance_variable_set(:@user, user)
        scenario.instance_variable_get(:@headers)['HTTP_AUTHORIZATION'] =
          "Basic #{Base64.strict_encode64("#{user}:fixture-only")}"
        run_operations(scenario, 1).first.first
      end
      expect(results.last.body).to eq(results.first.body)
      expect(results[1].body).not_to include('GROUP_SECRET', 'ACCOUNT_SECRET')
    end
  end

  it 'resets operation records, validates every response and rejects incomplete/extra calls' do
    with_scenario(rows: 1, include_depth: 2) do |scenario|
      scenario.reset!(iterations: 2)
      first = scenario.call
      expect { scenario.counters }.to raise_error(/incomplete/)
      second = scenario.call
      expect(scenario.validate!(first, index: 0)[:body_sha256]).to eq(Digest::SHA256.hexdigest(first.body))
      expect(scenario.validate!(second, index: 1)[:canonical_body]).to eq(JSON.parse(second.body))
      expect { scenario.validate!(first, index: -1) }.to raise_error(ArgumentError)
      expect { scenario.call }.to raise_error(/beyond/)
      scenario.reset!(iterations: 1)
      expect { scenario.validate!(first, index: 0) }.to raise_error(ArgumentError, /uncalled/)
      response = scenario.call
      scenario.validate!(response, index: 0)
      wrong = response.dup
      allow(wrong).to receive(:body).and_return(response.body.sub('group1', 'wrong!'))
      expect { scenario.validate!(wrong, index: 0) }.to raise_error(/rows or values/)
      expect { scenario.reset!(iterations: 0) }.to raise_error(ArgumentError)
    end
  end

  it 'owns a separate connection without changing the global ActiveRecord base or another scenario' do
    original_connected = ActiveRecord::Base.connected?
    original_pool = ActiveRecord::Base.connection_pool if original_connected
    first = described_class.build(id: 'sqlite.includes', dimensions: { rows: 1, include_depth: 2 })
    second = described_class.build(id: 'sqlite.includes', dimensions: { rows: 32, include_depth: 2 })
    first_pool = first.instance_variable_get(:@base).connection_pool
    second_pool = second.instance_variable_get(:@base).connection_pool
    expect(first_pool).not_to equal(second_pool)
    expect(ActiveRecord::Base.connected?).to eq(original_connected)
    expect(ActiveRecord::Base.connection_pool).to equal(original_pool) if original_pool
    first.close
    expect(first_pool.connected?).to be(false)
    expect { first.call }.to raise_error(/closed/)
    _responses, counts = run_operations(second, 1)
    expect(counts.first).to eq(queries: 3, authorizations: 65, executions: 1)
  ensure
    first&.close
    second&.close
  end
end
