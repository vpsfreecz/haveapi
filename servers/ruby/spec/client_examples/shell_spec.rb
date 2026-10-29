require 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

RSpec.describe HaveAPI::ClientExamples do
  let(:action) do
    { method: 'POST', path: '/widgets/{widget_id}', auth: false,
      input: { layout: :hash, namespace: :widget, parameters: { name: { type: 'String' } } },
      output: { layout: :hash, namespace: :widget, parameters: {} } }
  end
  let(:sample) { { path_params: [7], request: { name: 'ordinary' }, response: {}, status: true } }

  def renderer(type, base_url: 'https://docs.example/api/', version: '1', resource_path: ['widget'], action_name: 'update', contract: action)
    type.new('docs.example', base_url, version, resource_path, {}, action_name, contract)
  end

  def capture_arguments(source, directory)
    bin = File.join(directory, 'bin')
    FileUtils.mkdir_p(bin)
    %w[haveapi-cli curl].each do |name|
      executable = File.join(bin, name)
      File.write(executable, "#!/bin/sh\nprintf '%s\\0' \"$@\" > \"$CAPTURE\"\n")
      File.chmod(0o755, executable)
    end
    capture = File.join(directory, 'arguments')
    stdout, stderr, status = Open3.capture3(
      { 'PATH' => "#{bin}:#{ENV.fetch('PATH')}", 'CAPTURE' => capture },
      'sh', '-c', source.delete_prefix('$ ')
    )
    expect(status).to be_success, "#{stdout}\n#{stderr}"
    File.binread(capture).force_encoding(Encoding::UTF_8).split("\0", -1)[0...-1]
  end

  it 'keeps the reported CLI request-value breakout literal' do
    Dir.mktmpdir('haveapi-shell-') do |directory|
      marker = File.join(directory, 'request-value-executed')
      payload = "'; printf request-value-confirmed > #{marker}; #'"
      source = renderer(HaveAPI::ClientExamples::RubyCli).example(sample.merge(request: { name: payload }))
      argv = capture_arguments(source, directory)
      expect(File.exist?(marker)).to be(false)
      expect(argv).to eq(['-u', 'https://docs.example/api/', '--version', '1', 'widget', 'update', '7', '--', '--name', payload])
    end
  end

  it 'keeps the reported CLI base-URL separator literal' do
    Dir.mktmpdir('haveapi-shell-') do |directory|
      marker = File.join(directory, 'base-url-executed')
      base_url = "https://docs.example/api; printf host-confirmed > #{marker}; #"
      argv = capture_arguments(renderer(HaveAPI::ClientExamples::RubyCli, base_url:).init, directory)
      expect(File.exist?(marker)).to be(false)
      expect(argv).to eq(['-u', base_url, '--version', '1'])
    end
  end

  it 'keeps the reported curl JSON substitution literal' do
    Dir.mktmpdir('haveapi-shell-') do |directory|
      marker = File.join(directory, 'request-value-executed')
      payload = "$(printf request-value-confirmed > #{marker})"
      argv = capture_arguments(renderer(HaveAPI::ClientExamples::Curl).request(sample.merge(request: { name: payload })), directory)
      expect(File.exist?(marker)).to be(false)
      expect(argv).to eq(['--request', 'POST', '--data-binary', JSON.generate(widget: { name: payload }), 'https://docs.example/api/widgets/7'])
      expect(JSON.parse(argv.fetch(3))).to eq('widget' => { 'name' => payload })
    end
  end

  it 'keeps the reported curl URL quote breakout literal' do
    Dir.mktmpdir('haveapi-shell-') do |directory|
      marker = File.join(directory, 'base-url-executed')
      base_url = "https://docs.example/'$(printf host-confirmed > #{marker})'/api/"
      argv = capture_arguments(renderer(HaveAPI::ClientExamples::Curl, base_url:).request(sample), directory)
      expect(File.exist?(marker)).to be(false)
      expect(argv).to eq(['--request', 'POST', '--data-binary', JSON.generate(widget: { name: 'ordinary' }), "#{base_url}widgets/7"])
      expect(JSON.parse(argv.fetch(3))).to eq('widget' => { 'name' => 'ordinary' })
    end
  end

  it 'preserves CLI argument order, Boolean flags and existing to_s values across shell metacharacters' do
    Dir.mktmpdir('haveapi-shell-') do |directory|
      marker = File.join(directory, 'unintended')
      hostile = "space\tline\n雪'\"\\$value;`touch #{marker}`$(touch #{marker})"
      values = { 'odd_name' => hostile, empty: '', zero: 0, nil_value: nil,
                 list: [false, 0, nil], object: { nested: false }, enabled_flag: true, disabled_flag: false,
                 at_file: '@example', escaped_at: '@@example' }
      parameters = values.to_h { |key, _| [key, { type: 'String' }] }
      parameters[:enabled_flag] = parameters[:disabled_flag] = { type: 'Boolean' }
      contract = action.merge(input: action[:input].merge(parameters:))
      generator = renderer(HaveAPI::ClientExamples::RubyCli, base_url: hostile, version: hostile,
                                                             resource_path: [hostile, 'nested'], action_name: hostile, contract:)
      request = sample.merge(path_params: [hostile, '', 0, nil], request: values)
      argv = capture_arguments(generator.example(request), directory)
      expect(argv).to eq(['-u', hostile, '--version', hostile, "#{hostile}.nested", hostile, hostile, '', '0', '', '--',
                          '--odd-name', hostile, '--empty', '', '--zero', '0', '--nil-value', '',
                          '--list', values[:list].to_s, '--object', values[:object].to_s,
                          '--enabled-flag', '--no-disabled_flag', '--at-file', '@example', '--escaped-at', '@@example'])
      expect(File.exist?(marker)).to be(false)
      malicious_option = "option'; touch #{marker}; #"
      contract[:input][:parameters][malicious_option] = { type: 'String' }
      argv = capture_arguments(generator.example(sample.merge(request: { malicious_option => hostile })), directory)
      expect(argv.last(3)).to eq(['--', "--#{malicious_option}", hostile])
      expect(File.exist?(marker)).to be(false)
    end
  end

  it 'preserves curl methods, paths and complete JSON values without shell evaluation' do
    Dir.mktmpdir('haveapi-shell-') do |directory|
      marker = File.join(directory, 'unintended')
      hostile = "\t\n雪'\"\\$value;`touch #{marker}`$(touch #{marker})"
      values = { name: hostile, empty: '', enabled: false, zero: 0, nullable: nil,
                 nested: { list: [false, 0, nil, '', hostile] } }
      contract = action.merge(method: hostile, path: "/widgets/{widget_id}#{hostile}")
      argv = capture_arguments(renderer(HaveAPI::ClientExamples::Curl, contract:).request(sample.merge(path_params: [hostile], request: values)), directory)
      expect(argv).to eq(['--request', hostile, '--data-binary', JSON.generate(widget: values),
                          "https://docs.example/api/widgets/#{hostile}#{hostile}"])
      expect(JSON.parse(argv.fetch(3))).to eq(JSON.parse(JSON.generate(widget: values)))
      expect(File.exist?(marker)).to be(false)
    end
  end

  it 'keeps curl GET query construction and body semantics intact' do
    Dir.mktmpdir('haveapi-shell-') do |directory|
      values = { name: 'a &雪', enabled: false, zero: 0, nullable: nil }
      argv = capture_arguments(renderer(HaveAPI::ClientExamples::Curl, contract: action.merge(method: 'GET')).request(sample.merge(request: values)), directory)
      expect(argv).to eq(['--request', 'GET', '--data-binary', JSON.generate(widget: values),
                          'https://docs.example/api/widgets/7?name=a+%26%E9%9B%AA&enabled=false&zero=0&nullable='])
      expect(JSON.parse(argv.fetch(3))).to eq(JSON.parse(JSON.generate(widget: values)))
    end
  end

  it 'encodes curl initialization and auth URLs, token headers and login values once' do
    Dir.mktmpdir('haveapi-shell-') do |directory|
      marker = File.join(directory, 'unintended')
      hostile = "\n雪'\"\\$value;`touch #{marker}`$(touch #{marker})"
      generator = renderer(HaveAPI::ClientExamples::Curl, base_url: "https://docs.example/#{hostile}/", version: hostile)
      base = generator.base_url
      expect(capture_arguments(generator.init, directory)).to eq(['--request', 'OPTIONS', generator.version_url])
      basic = generator.auth(:basic, {})
      first = basic.split("\nPassword: secret", 2).first.split('$ ', 2).last
      last = basic.split('# Password given on the command line', 2).last.split('$ ', 2).last
      expect(capture_arguments("$ #{first}", directory)).to eq(['--request', 'OPTIONS', '--user', 'user', base])
      expect(capture_arguments("$ #{last}", directory)).to eq(['--request', 'OPTIONS', '--user', 'user:secret', base])
      description = { http_header: hostile, resources: { token: { actions: { request: { input: { parameters: {
        hostile => { type: 'String', required: true }, lifetime: { type: 'String', required: true }
      } } } } } } }
      token = generator.auth(:token, description)
      acquire, reuse = token.split("\n\n# Use a previously acquired token", 2)
      acquire = acquire.split('$ ', 2).last
      reuse = reuse.split('$ ', 2).last
      expect(capture_arguments("$ #{acquire}", directory)).to eq(['--request', 'POST', '--header', 'Content-Type: application/json',
                                                                  '--data-binary', JSON.generate(token: { hostile => hostile, lifetime: 'fixed' }),
                                                                  File.join(base, '_auth', 'token', 'tokens')])
      expect(capture_arguments("$ #{reuse}", directory)).to eq(['--request', 'OPTIONS', '--header', "#{hostile}: example-token", base])
      expect(File.exist?(marker)).to be(false)
    end
  end

  it 'encodes CLI Basic and token command spans without changing prompts or token options' do
    Dir.mktmpdir('haveapi-shell-') do |directory|
      marker = File.join(directory, 'unintended')
      hostile = "\n雪'\"\\$value;`touch #{marker}`$(touch #{marker})"
      generator = renderer(HaveAPI::ClientExamples::RubyCli, base_url: hostile, version: hostile)
      basic = generator.auth(:basic, {})
      first, last = basic.split("\n\n# If username", 2)
      first = first.split('$ ', 2).last
      last = last.split('$ ', 2).last.split("\nPassword: secret", 2).first
      prefix = ['-u', hostile, '--version', hostile]
      expect(capture_arguments("$ #{first}", directory)).to eq(prefix + %w[--auth basic --user user --password secret])
      expect(capture_arguments("$ #{last}", directory)).to eq(prefix + %w[--auth basic --user user])
      description = { resources: { token: { actions: { request: { input: { parameters: {
        hostile => { type: 'String', required: true }, lifetime: { type: 'String', required: true }, password: { type: 'String' }
      } } } } } } }
      token = generator.auth(:token, description)
      first = token.split("\nPassword: secret", 2).first.split('$ ', 2).last
      last = token.split('# nor password and be authenticated', 2).last.split('$ ', 2).last
      expect(capture_arguments("$ #{first}", directory)).to eq(prefix + ['--auth', 'token', "--#{hostile}", hostile, '--lifetime', 'fixed', '--save', 'user', 'current'])
      expect(capture_arguments("$ #{last}", directory)).to eq(prefix + %w[user current])
      expect(token).to include('Password: secret')
      expect(File.exist?(marker)).to be(false)
    end
  end
end
