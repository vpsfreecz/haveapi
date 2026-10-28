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

  GROUPS = %w[init-examples auth-basic-examples auth-token-examples auth-oauth2-examples
              example-constructor.resources-new-0-examples example-constructor.resources-new-1-examples].freeze

  class DetailMap < Hash
    def []=(key, value)
      raise "Duplicate example detail declaration: #{key}" if has_key?(key)

      super
    end
  end

  def self.attributes(source)
    entries = source.scan(/([a-z][a-z0-9-]*)="([^"]*)"/)
    raise 'Duplicate example HTML attribute' unless entries.map(&:first).uniq.length == entries.length

    entries.to_h.transform_values { |value| CGI.unescapeHTML(value) }
  end

  def self.extract(html, detail: :thorough)
    raise 'Invalid requested example detail' unless %i[simple thorough].include?(detail)

    groups = html.scan(%r{<div\b([^>]*\bdata-example(?=\s|>)[^>]*)>(.*?)</div>}m)
    raise 'Malformed example group' unless groups.length == html.scan(/<div\b[^>]*\bdata-example(?=\s|>)/).length

    ids = []
    groups.flat_map do |attributes, body|
      group = self.attributes(attributes)
      id = group.fetch('id')
      raise "Duplicate example group: #{id}" if ids.include?(id)

      ids << id
      declarations = JSON.parse(group.fetch('data-example-details'), object_class: DetailMap)
      unless declarations.is_a?(Hash) && declarations.all? do |client, levels|
        client.is_a?(String) && [%w[simple], %w[simple thorough]].include?(levels)
      end
        raise "Invalid example detail declarations: #{id}"
      end

      actual = body.scan(%r{<details\b([^>]*\bdata-example-panel\b[^>]*)>(.*?)</details>}m)
      VARIANTS.map do |variant|
        levels = declarations.fetch(variant)
        effective = levels.include?(detail.to_s) ? detail.to_s : 'simple'
        variants = actual.select { |data, _code| self.attributes(data)['data-client'] == variant }
        unless variants.map { |data, _code| self.attributes(data)['data-detail'] }.sort == levels.sort
          raise "Missing, duplicate or undeclared example panels: #{id}/#{variant}"
        end

        data, code_body = variants.find { |data, _code| self.attributes(data)['data-detail'] == effective }
        panel = self.attributes(data)
        code = code_body.scan(%r{<pre><code class="([^"]+)">(.*?)</code></pre>}m)
        unless code.length == 1 && code[0][0] == variant.split('-').first && !code_body.include?('class="client-limitation"')
          raise "Expected one code panel: #{id}/#{variant}/#{effective}"
        end

        { group: id, id: panel.fetch('id'), variant:, language: code[0][0], requested_detail: detail,
          detail: effective.to_sym, source: CGI.unescapeHTML(code[0][1]) }
      end
    end
  end

  def self.validate_coverage!(panels)
    VARIANTS.each do |variant|
      selected = panels.select { |panel| panel[:variant] == variant }
      raise "Incomplete rendered coverage for #{variant}" unless selected.map { |panel| panel[:group] }.sort == GROUPS.sort

      selected.each do |panel|
        singleton = %w[javascript-callback typescript-callback].include?(variant) && !panel[:group].start_with?('example-')
        expected = singleton ? :simple : :thorough
        unless panel[:requested_detail] == :thorough && panel[:detail] == expected
          raise "Unexpected effective example detail: #{panel[:group]}/#{variant}"
        end
      end
    end
    unless panels.length == 36 && panels.count { |panel| panel[:detail] == :simple } == 8 &&
           panels.map { |panel| panel[:id] }.uniq.length == panels.length
      raise 'Unexpected rendered panel matrix'
    end
  end

  def self.receipt_delta(before, after)
    unless [before, after].all? { |receipt| receipt.is_a?(Hash) && receipt.keys.sort == %w[actions events] && receipt.values.all?(Array) }
      raise 'Invalid fixture receipt envelope'
    end

    before.to_h do |kind, previous|
      current = after.fetch(kind)
      raise 'Fixture receipts changed before the run boundary' unless current.take(previous.length) == previous

      [kind, current.drop(previous.length)]
    end
  end

  def self.authenticated_discovery(events, provider)
    events.each_index.find do |index|
      event = events[index]
      request = event['type'] == 'request' && event['method'] == 'OPTIONS' && event['path'] == '/mount/v2/' &&
                event['status'] == 200 && event['provider'] == provider && event['authenticated'] == !provider.nil?
      request && (provider.nil? || events.take(index).any? do |previous|
        previous['type'] == 'authentication' && previous['provider'] == provider && previous['authenticated'] == true
      end)
    end
  end

  def self.verify_completion!(panel, output, delta)
    raise "Failed callback: #{panel[:id]}" if output.include?('Discovery or authentication failed')

    actions = delta.fetch('actions')
    events = delta.fetch('events')
    if panel[:group].start_with?('example-')
      raise "Rendered action did not execute once: #{panel[:id]}" unless actions.length == 1

      receipt = actions.first
      expected = { 'name' => '', 'enabled' => false, 'nullable' => nil, 'payload' => DynamicDocumentationAPI::PAYLOAD }
      raise "Changed request values: #{receipt.inspect}" unless receipt['input'].except('count') == expected
      raise 'Changed mounted path arguments' unless receipt['path'].map(&:to_s) == ['7', 'name with space']

      count = panel[:group] == GROUPS.last ? -1 : 0
      raise 'Changed sample success/failure input' unless receipt['input']['count'] == count

      unless authenticated_discovery(events, 'token') && events.none? { |event| event['type'].start_with?('token_') }
        raise "Existing-token action authentication did not complete: #{panel[:id]}"
      end

      marker = count < 0 ? 'DOC_FAILURE' : 'DOC_SUCCESS'
      raise "Wrong result/error handling: #{panel[:id]}\n#{output}" unless output.include?(marker)
    else
      raise "Unexpected action during setup: #{panel[:id]}" unless actions.empty?

      provider = panel[:group] == 'init-examples' ? nil : panel[:group].delete_prefix('auth-').delete_suffix('-examples')
      discovery = authenticated_discovery(events, provider)
      raise "Discovery/authentication did not complete: #{panel[:id]}" unless discovery

      if provider == 'token'
        sequence = events.map { |event| event['type'] }
        request = sequence.index('token_request')
        verification = sequence.index('token_verification')
        unless provider == 'token' && request && verification && request < verification && verification < discovery
          raise "Token challenge did not complete: #{panel[:id]}"
        end
      end
      if panel[:detail] == :thorough
        marker = provider ? 'Authenticated' : 'Discovery complete'
        raise "Missing completion output: #{panel[:id]}\n#{output}" unless output.include?(marker)
      end
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
          validate_coverage!(panels)
          executions = []
          panels.each_with_index do |panel, index|
            extension = { 'typescript' => '.ts', 'javascript' => '.mjs', 'python' => '.py' }.fetch(panel[:language])
            name = "example-#{index}#{extension}"
            path = File.join(consumer, name)
            File.write(path, panel[:source])
            File.write(File.join(output, name), panel[:source])
            env = { 'NODE_PATH' => nil, 'PYTHONPATH' => nil, 'PYTHONHOME' => nil }
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
            begin
              result = run!(*command, chdir: consumer, env:, log_path: File.join(output, "example-#{index}.log"))
            ensure
              after = JSON.parse(request("#{base}/__acceptance_receipts"))
              delta = receipt_delta(before, after)
              File.write(File.join(output, "example-#{index}-receipts.json"), JSON.pretty_generate(delta))
            end
            verify_completion!(panel, result, delta)
            executions << panel.except(:source).merge(challenge_completion: panel[:group] == 'auth-token-examples')
          end
          raise 'Incomplete token challenge coverage' unless executions.count { |execution| execution[:challenge_completion] } == VARIANTS.length

          File.write(File.join(output, 'result.json'), JSON.pretty_generate({ panels: panels.length, variants: VARIANTS,
                                                                              details: panels.group_by { |panel| panel[:detail] }.transform_values(&:length),
                                                                              challenge_completions: VARIANTS.length, executions:, status: 'passed' }))
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
