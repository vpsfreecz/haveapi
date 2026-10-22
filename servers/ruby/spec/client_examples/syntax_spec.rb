# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'tempfile'
require 'haveapi/client_examples/curl'
require 'haveapi/client_examples/http'
require 'haveapi/client_examples/js_client'
require 'haveapi/client_examples/php_client'
require 'haveapi/client_examples/ruby_client'

describe HaveAPI::ClientExamples do
  let(:action) do
    {
      method: 'POST',
      path: '/v1/widgets/{widget_id}/update',
      input: {
        layout: :hash,
        namespace: :widget,
        parameters: {
          name: { type: 'String' },
          enabled: { type: 'Boolean' }
        }
      },
      output: {
        layout: :hash,
        namespace: :widget,
        parameters: {
          id: { type: 'Integer' },
          name: { type: 'String' }
        }
      }
    }
  end
  let(:sample) do
    {
      path_params: [101],
      request: { name: 'documented widget', enabled: true },
      response: { id: 101, name: 'documented widget' },
      status: true,
      message: nil,
      errors: nil,
      http_status: 200
    }
  end
  let(:client_args) do
    [
      'api.example.test',
      'https://api.example.test',
      1,
      %w[widget],
      {},
      'update',
      action
    ]
  end

  def syntax_check(command, source, suffix)
    Tempfile.create(['haveapi-example-', suffix]) do |file|
      file.write(source)
      file.flush
      output, status = Open3.capture2e(*command, file.path)
      [status, output]
    end
  end

  it 'generates valid JavaScript' do
    source = HaveAPI::ClientExamples::JsClient.new(*client_args).example(sample)
    status, output = syntax_check(%w[node --check], source, '.mjs')

    expect(status).to be_success, output
  end

  it 'generates valid PHP' do
    source = HaveAPI::ClientExamples::PhpClient.new(*client_args).example(sample)
    status, output = syntax_check(%w[php -l], "<?php\n#{source}", '.php')

    expect(status).to be_success, output
  end

  it 'generates valid Ruby' do
    source = HaveAPI::ClientExamples::RubyClient.new(*client_args).example(sample)
    status, output = syntax_check(%w[ruby -c], source, '.rb')

    expect(status).to be_success, output
  end

  it 'generates shell-parseable curl requests' do
    source = HaveAPI::ClientExamples::Curl.new(*client_args).request(sample)
    status, output = syntax_check(%w[bash -n], source, '.sh')

    expect(status).to be_success, output
  end

  it 'generates structurally valid HTTP requests and responses' do
    generator = HaveAPI::ClientExamples::Http.new(*client_args)
    request_headers, request_body = generator.request(sample).split("\n\n", 2)
    request_lines = request_headers.lines(chomp: true)

    expect(request_lines.shift).to eq('POST /v1/widgets/101/update HTTP/1.1')
    expect(request_lines).to include('Host: api.example.test', 'Content-Type: application/json')
    expect(JSON.parse(request_body)).to eq(
      'widget' => {
        'name' => 'documented widget',
        'enabled' => true
      }
    )

    response_headers, response_body = generator.response(sample).split("\n\n", 2)
    response_lines = response_headers.lines(chomp: true)
    expect(response_lines.shift).to eq('HTTP/1.1 200 OK')
    content_length = response_lines
                     .find { |line| line.start_with?('Content-Length: ') }
                     .split(': ', 2)
                     .last
                     .to_i
    expect(content_length).to eq(response_body.bytesize)
    expect(JSON.parse(response_body)).to include('status' => true)
  end
end
