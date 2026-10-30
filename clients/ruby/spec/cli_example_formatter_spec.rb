require 'fileutils'
require 'open3'
require 'stringio'
require 'tmpdir'
require_relative '../lib/haveapi/cli'

RSpec.describe HaveAPI::CLI::ExampleFormatter do
  def format_request(request, program: 'haveapi-cli', resources: ['widget'], action_name: 'update',
                     parameters: { name: { type: 'String' } }, title: '', response: {}, receiver: nil)
    action = Object.new
    action.define_singleton_method(:examples) { [{ title: title, request: request, response: response }] }
    action.define_singleton_method(:resource_path) { resources }
    action.define_singleton_method(:name) { action_name }
    action.define_singleton_method(:param_description) { |_direction, name| parameters[name] }
    action.define_singleton_method(:namespace) { |_direction| :widget }
    cli = Object.new
    cli.define_singleton_method(:format_output) { |*args| receiver&.call(*args) }
    out = StringIO.new
    saved = $0
    begin
      $0 = program
      described_class.format_examples(cli, action, out)
    ensure
      $0 = saved
    end
    out.string
  end

  def capture_arguments(source, directory, program: 'haveapi-cli')
    executable = File.join(directory, program)
    File.write(executable, "#!/bin/sh\nprintf '%s\\0' \"$@\" > \"$CAPTURE\"\n")
    File.chmod(0o755, executable)
    capture = File.join(directory, 'arguments')
    stdout, stderr, status = Open3.capture3(
      { 'PATH' => "#{directory}:#{ENV.fetch('PATH')}", 'CAPTURE' => capture },
      'sh', '-c', source.delete_prefix('$ '), chdir: directory
    )
    expect(status).to be_success, "#{stdout}\n#{stderr}"
    File.binread(capture).force_encoding(Encoding::UTF_8).split("\0", -1)[0...-1]
  end

  it 'keeps the reported CLI-help request substitution literal', :aggregate_failures do
    Dir.mktmpdir('haveapi-cli-help-') do |directory|
      marker = File.join(directory, 'request-value-executed')
      payload = "$(printf request-value-confirmed > #{marker})"
      source = format_request({ name: payload })
      argv = capture_arguments(source, directory)
      expect(File.exist?(marker)).to be(false)
      expect(argv).to eq(['widget', 'update', '--', '--name', payload])
    end
  end

  it 'preserves every complete CLI-help token and existing conversions without evaluation' do
    Dir.mktmpdir('haveapi-cli-help-') do |directory|
      hostile = "space\tline\n雪'\"\\$value;`touch unintended`$(touch unintended)"
      program = "cli #{hostile}"
      option = "odd_name #{hostile}"
      values = { option => hostile, empty: '', zero: 0, nil_value: nil, list: [false, 0, nil], object: { key: false },
                 enabled_flag: true, disabled_flag: false, nil_flag: nil, at_file: '@example', escaped_at: '@@example', unknown: 'filtered' }
      parameters = values.except(:unknown).to_h { |key, _| [key, { type: 'String' }] }
      %i[enabled_flag disabled_flag nil_flag].each { |key| parameters[key] = { type: 'Boolean' } }
      source = format_request(values, program: program, resources: [hostile, 'nested'], action_name: hostile, parameters: parameters)
      argv = capture_arguments(source, directory, program: program)
      expect(argv).to eq(["#{hostile}.nested", hostile, '--', "--#{option.tr('_', '-')}", hostile,
                          '--empty', '', '--zero', '0', '--nil-value', '', '--list', values[:list].to_s,
                          '--object', values[:object].to_s, '--enabled-flag', '--no-disabled-flag', '--no-nil-flag',
                          '--at-file', '@example', '--escaped-at', '@@example'])
      expect(File.exist?(File.join(directory, 'unintended'))).to be(false)
    end
  end

  it 'keeps absent inputs, filtering, title and response output routing intact' do
    saved = $0
    calls = []
    receiver = proc do |action, response, out|
      calls << [action.name, response, out.class]
      out << "formatted response\n"
    end
    source = format_request(nil, title: 'Visible title', response: { id: 0 }, receiver: receiver)
    expect(source).to eq(" > Visible title:\n$ haveapi-cli widget update\nformatted response\n")
    expect(calls).to eq([['update', { widget: { id: 0 } }, StringIO]])
    expect(format_request({})).to eq("$ haveapi-cli widget update\n")
    expect(format_request({ unknown: 'filtered' })).to eq("$ haveapi-cli widget update --\n")
    expect($0).to eq(saved)
  end
end
