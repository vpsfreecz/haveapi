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
require 'haveapi/client'

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
          enabled: { type: 'Boolean' },
          group_by: { type: 'Custom' }
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
      request: {
        name: "documented \"widget\" with $value and an apostrophe's backslash \\",
        enabled: true,
        group_by: ['vps_id', "owner's $group\\path"]
      },
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

  def execute_ruby(source)
    Tempfile.create(['haveapi-handler-', '.rb']) do |file|
      file.write(source)
      file.flush
      load file.path
    end
  end

  it 'generates valid JavaScript' do
    result = HaveAPI::ClientExamples::JsClient.new(*client_args).example(sample)
    source = result.is_a?(Hash) ? result.fetch(:code) : result
    status, output = syntax_check(%w[node --check], source, '.mjs')

    expect(status).to be_success, output
  end

  it 'generates valid PHP' do
    source = HaveAPI::ClientExamples::PhpClient.new(*client_args).example(sample)
    status, output = syntax_check(%w[php -l], "<?php\n#{source}", '.php')

    expect(status).to be_success, output
    expect(source).to include(
      "'group_by' => ['vps_id', 'owner\\'s $group\\\\path']"
    )
    expect(source).to include(
      "'name' => 'documented \"widget\" with $value and an apostrophe\\'s backslash \\\\'"
    )
  end

  it 'generates valid Ruby' do
    source = HaveAPI::ClientExamples::RubyClient.new(*client_args).example(sample)
    status, output = syntax_check(%w[ruby -c], source, '.rb')

    expect(status).to be_success, output
  end

  it 'round-trips PHP data literals through plain and Thorough source without changing control bytes' do
    renderer = HaveAPI::ClientExamples::PhpClient.new(*client_args)
    values = ['', '$user', "quote'\"\\", "line\n    indented\r\n\t$value\\\x00\x1f\x7f ž", false, nil, 0]
    body = "echo json_encode(#{renderer.value(values)});"
    [body, renderer.with_error_handling(body)].each do |source|
      output, status = Open3.capture2e('php', stdin_data: "<?php\n#{source}")
      expect(status).to be_success, output
      expect(JSON.parse(output)).to eq(values)
    end
    expect(renderer.value('public literal')).to eq("'public literal'")
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
        'name' => "documented \"widget\" with $value and an apostrophe's backslash \\",
        'enabled' => true,
        'group_by' => ['vps_id', "owner's $group\\path"]
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

  it 'runs the Ruby handlers with actual client exception classes and propagates unknown errors' do
    context = HaveAPI::ClientExample::Context.new(version: '1', host: 'api.test', base_url: 'https://api.test/',
                                                  version_url: 'https://api.test/v1/', description: {},
                                                  resource_path: ['widget'], action_name: 'update', action:, sample:, detail: :thorough)
    client_type = Class.new(HaveAPI::Client::Client) { attr_accessor :widget }
    client = instance_double(client_type, setup: nil, authenticate: nil)
    allow(HaveAPI::Client).to receive(:new).and_return(client)
    failure_action = Object.new
    def failure_action.client_message(_key, **values)
      values[:message] || 'validation failure'
    end

    def failure_action.name
      'update'
    end
    response = HaveAPI::Client::Response.new(failure_action, { status: false, message: 'API failure', errors: { count: ['bad'] } })
    errors = [HaveAPI::Client::ValidationError.new(failure_action, { count: ['bad'] }),
              HaveAPI::Client::ActionFailed.new(response),
              HaveAPI::Client::Authentication::AuthenticationFailed.new('authentication failure'),
              HaveAPI::Client::ProtocolError.new('protocol failure'), RestClient::Exception.new,
              JSON::ParserError.new('invalid JSON')]
    source = HaveAPI::ClientExamples::RubyClient.render(:init, context:).fetch(:code)
    errors.each do |error|
      allow(client).to receive(:setup).and_raise(error)
      expect { execute_ruby(source) }.to output(/./).to_stderr
    end
    expect(client).to have_received(:setup).exactly(errors.length).times
    allow(client).to receive(:setup).and_return(nil)
    allow(client).to receive(:authenticate).and_raise(errors[2])
    auth = HaveAPI::ClientExamples::RubyClient.render(:auth, context:, auth_method: :basic, auth_description: {}).fetch(:code)
    expect { execute_ruby(auth) }.to output(/authentication failure/).to_stderr
    allow(client).to receive(:setup).and_return(nil)
    widget_type = Class.new do
      def update(*); end
    end
    widget = instance_double(widget_type)
    allow(client).to receive(:widget).and_return(widget)
    allow(widget).to receive(:update).and_raise(errors[0])
    action_source = HaveAPI::ClientExamples::RubyClient.render(:example, context:).fetch(:code)
    expect { execute_ruby(action_source) }.to output(/validation failure/).to_stderr
    allow(client).to receive(:setup).and_raise(RuntimeError, 'unknown dependency failure')
    expect { execute_ruby(source) }.to raise_error(RuntimeError, 'unknown dependency failure')
    expect(source.index('ValidationError')).to be < source.index('ActionFailed')
    expect(source).to include('error.response.is_a?(HaveAPI::Client::Response)')
  end

  it 'runs PHP handlers with real framework error objects and rethrows unknown dependency exceptions' do
    root = File.expand_path('../../../..', __dir__)
    renderer = HaveAPI::ClientExamples::PhpClient.new(*client_args)
    prefix = <<~PHP
      <?php
      require #{renderer.value(File.join(root, 'clients/php/src/Client/Exception/Base.php'))};
      require #{renderer.value(File.join(root, 'clients/php/src/Client/Exception/ValidationError.php'))};
      require #{renderer.value(File.join(root, 'clients/php/src/Client/Exception/ActionFailed.php'))};
      require #{renderer.value(File.join(root, 'clients/php/src/Client/Exception/AuthenticationFailed.php'))};
      require #{renderer.value(File.join(root, 'clients/php/src/Client/Exception/ProtocolError.php'))};
      require #{renderer.value(File.join(root, 'clients/php/src/Client/Response.php'))};
      $wire = (object) ['code' => 400, 'body' => (object) ['status' => false, 'message' => 'API failure', 'errors' => ['count' => ['bad']]]];
      $response = new \\HaveAPI\\Client\\Response(null, $wire, 0);
    PHP
    errors = [
      'new \\HaveAPI\\Client\\Exception\\ValidationError("update", ["count" => ["bad"]])',
      'new \\HaveAPI\\Client\\Exception\\ActionFailed($response, "API failure")',
      'new \\HaveAPI\\Client\\Exception\\AuthenticationFailed("authentication failure")',
      'new \\HaveAPI\\Client\\Exception\\ProtocolError("protocol failure")'
    ]
    errors.each do |error|
      script = prefix + "$failure = #{error};\n" + renderer.with_error_handling('throw $failure;')
      output, status = Open3.capture2e('php', stdin_data: script)
      expect(status).to be_success, output
      expect(output).not_to be_empty
    end
    script = "#{prefix}$failure = new \\RuntimeException('unknown dependency');\ntry {\n" \
             "#{renderer.with_error_handling('throw $failure;')}" \
             "} catch (\\RuntimeException $error) { echo 'UNKNOWN_PROPAGATED'; }\n"
    output, status = Open3.capture2e('php', stdin_data: script)
    expect(status).to be_success, output
    expect(output).to include('UNKNOWN_PROPAGATED')
    context = HaveAPI::ClientExample::Context.new(version: '1', host: 'api.test', base_url: 'https://api.test/',
                                                  version_url: 'https://api.test/v1/', description: {}, detail: :thorough)
    source = HaveAPI::ClientExamples::PhpClient.render(:auth, context:, auth_method: :oauth2, auth_description: {}).fetch(:code)
    status, output = syntax_check(%w[php -l], "<?php\n#{source}", '.php')
    expect(status).to be_success, output
    expect(source).to include('session_start()', 'requestAuthorizationCode()', 'requestAccessToken()', "$_SESSION['access_token']")
    expect(source).not_to include('Throwable', 'getResponse()->http_status')
  end

  it 'keeps Ruby token-login literals truthy through the actual runtime option filter' do
    fields = { user: { type: 'String', required: true }, password: { type: 'String', required: true },
               enabled: { type: 'Boolean', required: true },
               custom: { type: 'Custom', nullable: true, required: false,
                         validators: { include: { values: [nil, 'public-choice'] } } } }
    continuation = { confirmation: { type: 'Boolean', required: true, validators: { accept: { value: false } } },
                     empty: { type: 'Custom', nullable: true, required: false, validators: { accept: { value: nil } } } }
    description = { resources: { token: { actions: { request: { input: { parameters: fields } },
                                                     verify: { input: { parameters: continuation } } } } } }
    definitions = HaveAPI::Params.new(:input, nil)
    definitions.layout = :hash
    definitions.namespace = false
    definitions.custom(:custom, nullable: true, required: false, default: 'public-choice', fill: true, choices: [nil, 'public-choice'])
    expect(definitions.params.first).to be_optional
    expect(definitions.params.first).to be_nullable
    expect(definitions.validate({ custom: nil })).to eq(custom: nil)
    expect(definitions.validate({})).to eq(custom: 'public-choice')
    before = Marshal.dump(description)
    renderer = HaveAPI::ClientExamples::RubyClient.new(*client_args)
    options = renderer.send(:auth_token_credentials, description).transform_keys(&:to_sym)
    expect(options).to include(enabled: true, custom: 'public-choice')
    finite = Marshal.load(Marshal.dump(description))
    finite[:resources][:token][:actions][:request][:input][:parameters][:enabled][:validators] = { include: { values: [false, true] } }
    expect(renderer.send(:auth_token_credentials, finite)).to include('enabled' => true)
    provider = HaveAPI::Client::Authentication::Token.allocate
    provider.instance_variable_set(:@opts, options)
    provider.instance_variable_set(:@desc, description)
    allow(provider).to receive(:login_step).and_return(:done)
    provider.send(:request_token)
    expect(provider).to have_received(:login_step).with(:request, include(enabled: true, custom: 'public-choice'))
    expect(renderer.send(:auth_token_continuations, description).fetch('verify')).to eq('confirmation' => false, 'empty' => nil)
    expect(Marshal.dump(description)).to eq(before)
    php = HaveAPI::ClientExamples::PhpClient.new(*client_args)
    expect(php.send(:auth_token_credentials, description)).to include('enabled' => false, 'custom' => 'public-choice')
    root = File.expand_path('../../../..', __dir__)
    script = <<~PHP
      <?php
      require #{php.value(File.join(root, 'clients/php/src/Client/Authentication/Base.php'))};
      require #{php.value(File.join(root, 'clients/php/src/Client/Authentication/Token.php'))};
      new class(#{php.value(php.send(:auth_token_credentials, description))}) extends \\HaveAPI\\Client\\Authentication\\Token {
          public function __construct($options) { $this->opts = $options; $this->requestToken(); }
          protected function getRequestCredentials() { return ["user", "password", "enabled", "custom"]; }
          protected function runAuthentication($action, $input) { echo json_encode($input); }
      };
    PHP
    output, status = Open3.capture2e('php', stdin_data: script)
    expect(status).to be_success, output
    expect(JSON.parse(output)).to include('enabled' => false, 'custom' => 'public-choice')
    # The same real PHP method loses explicit null before the request boundary.
    dropped_script = script.sub(php.value(php.send(:auth_token_credentials, description)),
                                php.value({ 'user' => 'user', 'password' => 'secret', 'enabled' => false, 'custom' => nil }))
    dropped_output, dropped_status = Open3.capture2e('php', stdin_data: dropped_script)
    expect(dropped_status).to be_success, dropped_output
    dropped = JSON.parse(dropped_output)
    expect(dropped).to include('enabled' => false)
    expect(dropped).not_to have_key('custom')

    js = HaveAPI::ClientExamples::JsClient.new(*client_args)
    expect(js.send(:auth_token_credentials, description)).to include('enabled' => false, 'custom' => nil)
    expect(HaveAPI::ClientExamples::PythonClient.new(*client_args).send(:auth_token_credentials, description))
      .to include('enabled' => false, 'custom' => nil)
  end

  it 'limits required Ruby false and optional nullable Ruby/PHP null-only login choices' do
    ruby = HaveAPI::ClientExamples::RubyClient
    php = HaveAPI::ClientExamples::PhpClient
    boolean = { type: 'Boolean', required: true, validators: { accept: { value: false } } }
    custom = { type: 'Custom', nullable: true, required: false, validators: { include: { values: [nil] } } }
    context = HaveAPI::ClientExample::Context.new(version: '1', host: 'api.test', base_url: 'https://api.test/',
                                                  version_url: 'https://api.test/v1/', description: {})
    null_acceptance = custom.merge(validators: { accept: { value: nil } })
    [[ruby, boolean], [ruby, custom], [php, custom], [ruby, null_acceptance], [php, null_acceptance],
     [ruby, boolean.merge(required: false)]].each do |renderer, parameter|
      description = { resources: { token: { actions: { request: { input: { parameters: { required_input: parameter } } } } } } }
      %i[simple thorough].each do |detail|
        result = renderer.render(:auth, context: context.with(detail:), auth_method: :token, auth_description: description)
        expect(result).to include(status: :limitation)
        expect(result[:reason]).to include('cannot send')
      end
    end
    fields = { resources: { token: { actions: { request: { input: { parameters: { enabled: boolean } } } } } } }
    expect(php.render(:auth, context:, auth_method: :token, auth_description: fields)[:status]).to eq(:code)
  end
end
