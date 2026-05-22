# frozen_string_literal: true

require 'spec_helper'

RSpec.describe HaveAPI::Client::Authentication::Token do
  let(:communicator) do
    Class.new do
      def url
        'https://api.example'
      end

      def verify_ssl
        true
      end
    end.new
  end

  let(:http_header) { 'X-HaveAPI-Auth-Token' }

  let(:description) do
    {
      http_header: http_header,
      query_parameter: 'auth_token',
      resources: { token: { actions: {} } }
    }
  end

  context 'when sending tokens in HTTP headers' do
    it 'uses RFC-safe token header names from the API description' do
      http_header = 'X-HaveAPI-Auth-Token'
      auth = described_class.new(
        communicator,
        description.merge(http_header: http_header),
        token: 'secret-token'
      )

      expect(auth.request_headers).to eq(http_header => 'secret-token')
    end

    it 'rejects description-controlled header names that can inject headers' do
      http_header = "X-HaveAPI-Auth-Token\r\nX-Injected-Token"
      auth = described_class.new(
        communicator,
        description.merge(http_header: http_header),
        token: 'secret-token'
      )

      expect { auth.request_headers }.to raise_error(
        ArgumentError,
        /invalid token authentication HTTP header name/
      )
    end

    it 'rejects header names outside the HTTP token grammar' do
      invalid_headers = [
        nil,
        '',
        'X HaveAPI Token',
        'X-HaveAPI-Token:',
        "X-HaveAPI-Token\n"
      ]

      invalid_headers.each do |http_header|
        auth = described_class.new(
          communicator,
          description.merge(http_header: http_header),
          token: 'secret-token'
        )

        expect { auth.request_headers }.to raise_error(ArgumentError)
      end
    end
  end

  context 'when sending tokens in query parameters' do
    let(:http_header) { "X-HaveAPI-Auth-Token\r\nX-Injected-Token" }

    it 'does not use the HTTP header name from the API description' do
      auth = described_class.new(
        communicator,
        description,
        token: 'secret-token',
        via: :query_param
      )

      expect(auth.request_headers).to eq({})
      expect(auth.request_query_params).to eq('auth_token' => 'secret-token')
    end
  end
end
