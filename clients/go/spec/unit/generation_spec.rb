# Exercise the real emitter offline without the component's live-server helper.
require 'tmpdir'
require 'stringio'
require 'haveapi/schema'
require 'haveapi/go_client'

RSpec.describe HaveAPI::GoClient::Generator do
  it 'matches existing from_description bytes, formats Go and never describes a live API' do
    description = {
      'help' => '/v1.0/', 'meta' => { 'namespace' => '_meta' }, 'authentication' => {},
      'resources' => { 'widget' => { 'actions' => { 'show' => {
        'path' => '/v1.0/widgets/{widget_id}', 'method' => 'GET', 'aliases' => [], 'auth' => false,
        'input' => { 'parameters' => {}, 'namespace' => 'widget', 'layout' => 'object' },
        'output' => { 'parameters' => { 'name' => { 'type' => 'String' } }, 'namespace' => 'widget', 'layout' => 'object' },
        'meta' => { 'global' => nil, 'object' => nil }
      } }, 'resources' => {} } }
    }
    schema = HaveAPI::Schema::Snapshot.from_description(
      description:, api_version: '1.0', protocol_version: '2.0', source_url: 'https://example.test/v1.0/', profile: 'fixture'
    )
    allow(HaveAPI::Client::Communicator).to receive(:new).and_raise('offline generation attempted discovery')
    Dir.mktmpdir('haveapi-go-saved-') do |root|
      path = File.join(root, 'schema.json')
      File.write(path, HaveAPI::Schema::Snapshot.canonical(schema))
      cli_output = File.join(root, 'cli')
      direct_output = File.join(root, 'direct')
      err = StringIO.new
      status = HaveAPI::GoClient::Cli.run([
                                            'generate', '--schema', path, '--api-version', '1.0', '--output', cli_output,
                                            '--module', 'example.test/widget-client', '--package', 'client'
                                          ], err:)
      expect(status).to eq(0), err.string
      direct = described_class.from_description(
        JSON.parse(JSON.generate(description), symbolize_names: true), direct_output,
        module: 'example.test/widget-client', package: 'client'
      )
      direct.generate
      direct.go_fmt
      expect(file_bytes(cli_output)).to eq(file_bytes(direct_output))
      sources = file_bytes(cli_output).values.join
      expect(sources).to include('Widget *ResourceWidget', 'Show *ActionWidgetShow', 'func (inv *ActionWidgetShowInvocation) SetPathParamInt', 'Name string')
      expect(HaveAPI::Client::Communicator).not_to have_received(:new)
    end
  end

  def file_bytes(root)
    Dir.glob('**/*', base: root).select { |path| File.file?(File.join(root, path)) }.to_h do |path|
      [path, File.binread(File.join(root, path))]
    end
  end
end
