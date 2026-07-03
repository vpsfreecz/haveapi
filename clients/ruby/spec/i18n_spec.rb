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
end
