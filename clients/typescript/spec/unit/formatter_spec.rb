require_relative '../spec_helper'
require_relative '../../lib/haveapi/typescript_client/formatter'
require 'rbconfig'

RSpec.describe HaveAPI::TypeScriptClient::Formatter do
  include TypeScriptFixtures

  let(:directory) { Dir.mktmpdir('haveapi-formatter-spec-') }
  let(:log) { File.join(directory, 'calls.jsonl') }
  let(:files) { { 'index.ts' => "export const value='raw';\n", 'resources/widget.ts' => "export {};\n" } }

  after { FileUtils.remove_entry(directory) }

  def executable(version: described_class::VERSION, body: '', version_status: 0)
    path = File.join(directory, 'prettier executable;literal')
    File.write(path, <<~RUBY)
      #!#{RbConfig.ruby}
      require 'json'
      File.open(#{log.inspect}, 'a') { |file| file.puts(JSON.generate(ARGV)) }
      if ARGV == ['--version']
        puts #{version.inspect}
        exit #{version_status}
      end
      #{body}
    RUBY
    File.chmod(0o755, path)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('PRETTIER', 'prettier').and_return(path)
    path
  end

  def state(output)
    Dir.glob('**/*', File::FNM_DOTMATCH, base: output).select { |path| File.file?(File.join(output, path)) }.to_h do |path|
      full = File.join(output, path)
      [path, [File.binread(full), File.mtime(full)]]
    end
  end

  it 'uses one version probe and one argv batch with the packaged policy and isolated inputs' do
    executable(body: <<~RUBY)
      abort 'foreign inputs' unless Dir.glob('**/*.ts').sort == #{files.keys.sort.inspect}
      abort 'ambient ignore file' if File.exist?('.prettierignore')
      File.write('index.ts', "export const value = \\"formatted\\";\\n")
    RUBY
    allow(ENV).to receive(:fetch).with('PRETTIER', 'prettier').and_return('./prettier executable;literal')
    formatter = Dir.chdir(directory) { described_class.new }
    result = formatter.format(files)
    expect(result.fetch('index.ts')).to eq("export const value = \"formatted\";\n")
    expect(result.keys).to eq(files.keys)
    expected_arguments = [
      ['--version'],
      ['--config', described_class::CONFIG, '--no-editorconfig', '--ignore-path', File::NULL,
       '--parser', 'typescript', '--write', '**/*.ts']
    ]
    expect(File.readlines(log).map { |line| JSON.parse(line) }).to eq(expected_arguments)
    expect(formatter.provenance).to eq(
      'name' => 'prettier', 'version' => '3.9.10', 'config_sha256' => Digest::SHA256.hexdigest("{}\n")
    )
  end

  it 'selects prettier on PATH when no override is present' do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('PRETTIER', 'prettier').and_return('prettier')
    allow(Open3).to receive(:capture3).with('prettier', '--version').and_return(["3.9.10\n", '', double(success?: true)])
    expect(described_class.new.version).to eq('3.9.10')
    expect(Open3).to have_received(:capture3).with('prettier', '--version').once
  end

  it 'rejects a missing tool without creating destination parents' do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('PRETTIER', 'prettier').and_return(File.join(directory, 'missing'))
    output = File.join(directory, 'missing-parent/src/generated')
    expect { HaveAPI::TypeScriptClient::Generator.new(schema: snapshot).generate(output:) }
      .to raise_error(HaveAPI::TypeScriptClient::Error, /Unable to run Prettier/)
    expect(Dir.children(directory)).to be_empty
  end

  it 'preserves existing output on version, probe and formatting failures' do
    executable
    output = File.join(directory, 'src/generated')
    generator = HaveAPI::TypeScriptClient::Generator.new(schema: snapshot)
    generator.generate(output:)
    before = state(output)
    [
      { version: '3.9.9' },
      { version_status: 1 },
      { body: "warn 'format failed'; exit 1" },
      { body: %q{File.binwrite('index.ts', "invalid\r\n")} },
      { body: "File.binwrite('index.ts', [255, 10].pack('C*'))" },
      { body: "File.unlink('index.ts')" }
    ].each do |options|
      executable(**options)
      [false, true].each do |check|
        expect { generator.generate(output:, check:) }.to raise_error(HaveAPI::TypeScriptClient::Error)
        expect(state(output)).to eq(before)
      end
    end
  end
end
