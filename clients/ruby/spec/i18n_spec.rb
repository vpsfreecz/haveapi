# frozen_string_literal: true

require 'spec_helper'

RSpec.describe HaveAPI::Client::Client do
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

  it 'sends the configured language header' do
    client = described_class.new(
      TEST_SERVER.base_url,
      language: 'cs-CZ',
      language_header: 'X-Language'
    )

    expect(client.communicator.language_headers).to eq('X-Language' => 'cs-CZ')
  end

  it 'updates and reports language options through the option interface' do
    client = described_class.new(TEST_SERVER.base_url)

    client.set_opts(language: 'cs-CZ', language_header: 'X-Language')

    expect(client.opts(:language, :language_header)).to eq(
      language: 'cs-CZ',
      language_header: 'X-Language'
    )
    expect(client.communicator.language_headers).to eq('X-Language' => 'cs-CZ')
  end

  it 'localizes local validation errors' do
    client = described_class.new(TEST_SERVER.base_url, language: 'cs')

    expect { client.test.echo(valid_params.merge(i: 'abc')) }
      .to raise_error(HaveAPI::Client::ValidationError) do |err|
        expect(err.message).to include('Vstupní parametry jsou neplatné')
        expect(err.errors[:i]).to include('není platné celé číslo')
      end
  end

  it 'accepts a value from localized choice metadata' do
    client = described_class.new(TEST_SERVER.base_url, language: 'cs')
    values = client.test.actions[:echo_choice]
                   .input_params[:format]
                   .dig(:validators, :include, :values)

    expect(values).to eq(archive: 'Archiv', stream: 'Proud')

    response = client.test.echo_choice(format: 'archive')

    expect(response[:format]).to eq('archive')
  end
end
