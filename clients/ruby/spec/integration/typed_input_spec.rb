# frozen_string_literal: true

require 'spec_helper'

RSpec.describe HaveAPI::Client::Client do
  let(:client) { described_class.new(TEST_SERVER.base_url) }
  let(:valid_params) do
    {
      i: 1,
      f: 1.0,
      b: true,
      dt: '2020-01-01T00:00:00Z',
      s: 'x',
      t: 'y'
    }
  end

  it 'coerces valid typed inputs' do
    res = client.test.echo(
      i: ' 42 ',
      f: 5,
      b: 'yes',
      dt: '2020-01-01T00:00:00Z',
      s: 123,
      t: false
    )

    expect(res).to be_a(HaveAPI::Client::Response)
    expect(res[:i]).to eq(42)
    expect(res[:f]).to eq(5.0)
    expect(res[:b]).to be(true)
    expect(res[:dt]).to match(/\A2020-01-01T00:00:00(?:Z|\+00:00)\z/)
    expect(res[:s]).to eq('123')
    expect(res[:t]).to eq('false')
  end

  it 'accepts exponent float strings' do
    res = client.test.echo(
      i: 1,
      f: '1e3',
      b: true,
      dt: '2020-01-01',
      s: 'ok',
      t: 'ok'
    )

    expect(res[:f]).to eq(1000.0)
  end

  it 'rejects invalid integer strings' do
    expect { client.test.echo(valid_params.merge(i: 'abc')) }
      .to raise_error(HaveAPI::Client::ValidationError) do |err|
        expect(err.errors).to include(:i)
        expect(err.errors[:i]).to include(a_string_matching(/not a valid integer/))
      end
  end

  it 'rejects non-integral floats for integers' do
    expect { client.test.echo(valid_params.merge(i: 12.3)) }
      .to raise_error(HaveAPI::Client::ValidationError) do |err|
        expect(err.errors).to include(:i)
        expect(err.errors[:i]).to include(a_string_matching(/not a valid integer/))
      end
  end

  it 'rejects invalid floats' do
    expect { client.test.echo(valid_params.merge(f: 'abc')) }
      .to raise_error(HaveAPI::Client::ValidationError) do |err|
        expect(err.errors).to include(:f)
        expect(err.errors[:f]).to include(a_string_matching(/not a valid float/))
      end
  end

  it 'rejects invalid boolean strings' do
    expect { client.test.echo(valid_params.merge(b: 'maybe')) }
      .to raise_error(HaveAPI::Client::ValidationError) do |err|
        expect(err.errors).to include(:b)
        expect(err.errors[:b]).to include(a_string_matching(/not a valid boolean/))
      end
  end

  it 'rejects invalid boolean integers' do
    expect { client.test.echo(valid_params.merge(b: 2)) }
      .to raise_error(HaveAPI::Client::ValidationError) do |err|
        expect(err.errors).to include(:b)
        expect(err.errors[:b]).to include(a_string_matching(/not a valid boolean/))
      end
  end

  it 'rejects invalid datetimes' do
    expect { client.test.echo(valid_params.merge(dt: 'yesterday')) }
      .to raise_error(HaveAPI::Client::ValidationError) do |err|
        expect(err.errors).to include(:dt)
        expect(err.errors[:dt]).to include(a_string_matching(/ISO 8601/))
      end
  end

  it 'rejects arrays for string params' do
    expect { client.test.echo(valid_params.merge(s: [1, 2])) }
      .to raise_error(HaveAPI::Client::ValidationError) do |err|
        expect(err.errors).to include(:s)
        expect(err.errors[:s]).to include(a_string_matching(/not a valid string/))
      end
  end

  it 'rejects hashes for text params' do
    expect { client.test.echo(valid_params.merge(t: { a: 1 })) }
      .to raise_error(HaveAPI::Client::ValidationError) do |err|
        expect(err.errors).to include(:t)
        expect(err.errors[:t]).to include(a_string_matching(/not a valid string/))
      end
  end

  it 'accepts nil for optional resource params' do
    res = client.test.echo_resource_optional(project: nil)

    expect(res).to be_a(HaveAPI::Client::Response)
    expect(res[:project_provided]).to be(true)
    expect(res[:project_nil]).to be(true)
    expect(res[:project]).to be_nil
  end

  it 'accepts nil for optional typed params' do
    res = client.test.echo_optional(dt: nil)

    expect(res).to be_a(HaveAPI::Client::Response)
    expect(res[:dt_provided]).to be(true)
    expect(res[:dt_nil]).to be(true)
    expect(res[:dt]).to be_nil
  end

  it 'accepts nil for optional typed params via GET' do
    res = client.test.echo_optional_get(dt: nil)

    expect(res).to be_a(HaveAPI::Client::Response)
    expect(res[:dt_provided]).to be(true)
    expect(res[:dt_nil]).to be(true)
    expect(res[:dt]).to be_nil
  end
end
