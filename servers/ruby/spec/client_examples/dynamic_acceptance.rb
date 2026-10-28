# Run after committed-deliverable review, with built npm and Python artifacts.
# The only code executed below comes from the real server's rendered HTML.
require 'cgi'
require 'fileutils'
require 'json'
require 'net/http'
require 'open3'
require 'tmpdir'
require 'timeout'
require_relative '../../test_support/dynamic_documentation_api'

module DynamicDocumentationAcceptance
  VARIANTS = %w[javascript-callback javascript-async typescript-callback typescript-async python-sync python-async].freeze
  PAGES = { overview: '', authentication: '?page=authentication', resource: '?resource=constructor.resources' }.freeze

  def self.run!(*command, chdir:, env: {}, log_path: nil)
    output, status = Open3.capture2e(env, *command, chdir:)
    File.write(log_path, output) if log_path
    raise "#{command.first} failed (#{status.exitstatus}):\n#{output}" unless status.success?

    output
  end

  def self.request(url)
    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: 10, read_timeout: 30) { |http| http.get(uri.request_uri) }
    raise "Fixture HTTP #{response.code}: #{response.body[0, 200]}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  def self.extract(html, detail: :thorough)
    html.scan(%r{<details\b([^>]*\bdata-example-panel\b[^>]*)>(.*?)</details>}m).filter_map do |attributes, body|
      data = attributes.scan(/([a-z][a-z0-9-]*)="([^"]*)"/).to_h
      variant = data['data-client']
      next unless VARIANTS.include?(variant) && data['data-detail'] == detail.to_s

      code = body.match(%r{<pre><code class="([^"]+)">(.*?)</code></pre>}m)
      next unless code

      { id: CGI.unescapeHTML(data.fetch('id')), variant:, language: code[1], detail:,
        source: CGI.unescapeHTML(code[2]) }
    end
  end

  def self.run(npm_artifact:, python_artifact:, typescript:, node_types:, output:)
    root = File.expand_path('../../../..', __dir__)
    FileUtils.mkdir_p(output)
    tools = { typescript: File.expand_path(typescript), node_types: File.expand_path(node_types) }
    npm_artifact = File.expand_path(npm_artifact)
    python_artifact = File.expand_path(python_artifact)
    Dir.mktmpdir('haveapi-dynamic-acceptance-') do |consumer|
      File.write(File.join(consumer, 'package.json'), JSON.generate({ private: true, type: 'module' }))
      run!('npm', 'install', '--ignore-scripts', '--no-audit', '--no-fund', npm_artifact, chdir: consumer,
                                                                                          env: { 'NODE_PATH' => nil })
      run!('uv', 'venv', '--python', '3.11', 'venv', chdir: consumer)
      python = File.join(consumer, 'venv/bin/python')
      run!('uv', 'pip', 'install', '--python', python, python_artifact, chdir: consumer)
      server_script = File.join(root, 'servers/ruby/test_support/dynamic_documentation_api.rb')
      Open3.popen2e('ruby', server_script, chdir: File.join(root, 'servers/ruby')) do |stdin, server_output, wait|
        stdin.close
        reader = nil
        begin
          base = Timeout.timeout(30) do
            loop do
              line = server_output.gets
              raise 'Documentation fixture exited before readiness' unless line
              break line.split.last if line.start_with?('DYNAMIC_DOCUMENTATION_READY ')
            end
          end
          reader = Thread.new { File.write(File.join(output, 'fixture.log'), server_output.read) }
          panels = PAGES.flat_map do |page, query|
            html = request("#{base}/mount/v2/#{query}")
            File.write(File.join(output, "documentation-#{page}.html"), html)
            extract(html)
          end
          raise 'No actual HTML code panels extracted' if panels.empty?

          VARIANTS.each do |variant|
            selected = panels.select { |panel| panel[:variant] == variant }
            raise "Incomplete rendered coverage for #{variant}" unless selected.length >= 4 &&
                                                                       selected.any? { |panel| panel[:id].start_with?('init-') } &&
                                                                       selected.any? { |panel| panel[:id].start_with?('auth-basic-') } &&
                                                                       selected.count { |panel| panel[:id].start_with?('example-') } >= 2
          end
          panels.each_with_index do |panel, index|
            extension = { 'typescript' => '.ts', 'javascript' => '.mjs', 'python' => '.py' }.fetch(panel[:language])
            name = "example-#{index}#{extension}"
            path = File.join(consumer, name)
            File.write(path, panel[:source])
            File.write(File.join(output, name), panel[:source])
            env = { 'NODE_PATH' => nil, 'PYTHONPATH' => nil, 'PYTHONHOME' => nil,
                    'HAVEAPI_USER' => 'fixture-user', 'HAVEAPI_PASSWORD' => 'fixture-password',
                    'HAVEAPI_TOKEN' => 'fixture-token', 'HAVEAPI_ACCESS_TOKEN' => 'fixture-access-token',
                    'HAVEAPI_AUTH_user' => JSON.generate('fixture-user'),
                    'HAVEAPI_AUTH_password' => JSON.generate('fixture-password'),
                    'HAVEAPI_AUTH_lifetime' => JSON.generate('fixed'),
                    'HAVEAPI_AUTH_scope' => JSON.generate('all'), 'HAVEAPI_CHALLENGE_code' => JSON.generate('123456') }
            if extension == '.ts'
              config = {
                compilerOptions: { target: 'ES2022', module: 'NodeNext', moduleResolution: 'NodeNext', strict: true,
                                   types: ['node'], typeRoots: [tools[:node_types]], outDir: 'compiled', skipLibCheck: false },
                files: [name]
              }
              File.write(File.join(consumer, 'tsconfig.json'), JSON.generate(config))
              file_list = run!('node', tools[:typescript], '-p', 'tsconfig.json', '--listFiles', chdir: consumer)
              raise 'Checkout HaveAPI declarations leaked into installed-package check' if file_list.lines.any? do |line|
                line.include?('/clients/js/src/') || (line.include?('haveapi.d.ts') && !line.start_with?(consumer))
              end

              path = File.join(consumer, 'compiled', "example-#{index}.js")
            end
            before = JSON.parse(request("#{base}/__acceptance_receipts"))
            command = panel[:language] == 'python' ? [python, path] : ['node', path]
            result = run!(*command, chdir: consumer, env:, log_path: File.join(output, "example-#{index}.log"))
            if panel[:id].start_with?('auth-token-')
              challenge_result = run!(*command, chdir: consumer, env: env.merge('HAVEAPI_TOKEN' => nil),
                                                log_path: File.join(output, "example-#{index}-challenge.log"))
              raise "Token challenge did not complete: #{panel[:id]}\n#{challenge_result}" unless challenge_result.include?('Authenticated')
            end
            after = JSON.parse(request("#{base}/__acceptance_receipts"))
            if panel[:id].start_with?('example-')
              raise "Rendered action did not execute: #{panel[:id]}\n#{result}" unless after.length == before.length + 1

              receipt = after.last
              expected = { 'name' => '', 'enabled' => false, 'nullable' => nil, 'payload' => DynamicDocumentationAPI::PAYLOAD }
              raise "Changed request values: #{receipt.inspect}" unless receipt['input'].except('count') == expected
              raise 'Changed mounted path arguments' unless receipt['path'].map(&:to_s) == ['7', 'name with space']

              marker = receipt['input']['count'] < 0 ? 'DOC_FAILURE' : 'DOC_SUCCESS'
              raise "Wrong result/error handling: #{panel[:id]}\n#{result}" unless result.include?(marker)
            else
              marker = panel[:id].start_with?('init-') ? 'Discovery complete' : 'Authenticated'
              raise "Discovery/authentication did not complete: #{panel[:id]}\n#{result}" unless result.include?(marker)
            end
          end
          File.write(File.join(output, 'result.json'), JSON.pretty_generate({ panels: panels.length, variants: VARIANTS, status: 'passed' }))
        ensure
          Process.kill('TERM', wait.pid) if wait.alive?
          wait.value
          reader&.join
        end
      end
    end
  end
end

if $0 == __FILE__
  require 'optparse'
  options = {}
  OptionParser.new do |parser|
    %i[npm_artifact python_artifact typescript node_types output].each do |key|
      parser.on("--#{key.to_s.tr('_', '-')} PATH") { |path| options[key] = path }
    end
  end.parse!
  raise 'Supply --npm-artifact, --python-artifact, --typescript, --node-types and --output' unless options.length == 5

  DynamicDocumentationAcceptance.run(**options)
end
