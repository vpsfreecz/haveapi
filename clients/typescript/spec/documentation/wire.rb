# Postreview only. Supply the prepared published haveapi-client@0.30.2 bundle:
# HAVEAPI_TYPESCRIPT_RUNTIME=/absolute/path/to/haveapi-client/dist/haveapi-client.js
# nix develop --command bundle exec ruby clients/typescript/spec/documentation/wire.rb
require 'rspec/core'
require_relative 'fixtures'
require_relative 'compilation'

include TypeScriptDocumentationFixtures
include TypeScriptDocumentationCompilation

runtime = File.expand_path(ENV.fetch('HAVEAPI_TYPESCRIPT_RUNTIME'))
runtime_types = File.join(File.dirname(runtime), 'types/haveapi.d.ts')
root = File.expand_path('../../../..', __dir__)
node = ENV.fetch('NODE', 'node')
Dir.mktmpdir('haveapi-typescript-rendered-wire-') do |directory|
  # Parent owns the loopback server; render against its exact ephemeral URL.
  reader, writer = IO.pipe
  child = Process.spawn(node, File.join(__dir__, 'wire.mjs'), directory, runtime, out: writer, err: $stderr)
  writer.close
  begin
    base = reader.readline.strip
    raise 'Invalid loopback fixture URL' unless base.match?(%r{\Ahttp://127\.0\.0\.1:\d+\z})

    cases = []
    %w[/ /mount/].each do |mount|
      schema = documentation_snapshot(mount:)
      %i[simple thorough].product(%w[public basic token index nested error alias]).each do |detail, kind|
        protected_schema = Marshal.load(Marshal.dump(schema))
        fixture_action(protected_schema)['auth'] = true if %w[basic token].include?(kind)
        context = case kind
                  when 'index' then documentation_context(protected_schema, action_name: 'index', base:)
                  when 'nested' then documentation_context(protected_schema, action_name: 'show', resource_path: %w[widget part], base:)
                  else documentation_context(protected_schema, base:)
                  end
        context.description['authentication'].delete('basic') if kind == 'token'
        context.action_name = 'change' if kind == 'alias'
        context.sample[:status] = false if kind == 'error'
        context.sample[:request]['name'] = 'reject' if kind == 'error'
        context.detail = detail
        adapter = documentation_adapter(protected_schema)
        result = adapter.render(kind: :example, context:)
        raise 'Wire sample unexpectedly limited' unless result[:status] == :code

        cases << { code: executable_documentation(adapter, context, result.fetch(:code)), kind:, mount:, detail: }
      end
    end
    stdout, stderr, status = compile_documentation(directory, documentation_snapshot, cases.map { |item| item[:code] }, runtime_types:, emit: true)
    abort("#{stdout}\n#{stderr}") unless status.success?
    File.write(File.join(directory, 'cases.json'), JSON.generate(cases.map { |item| item.slice(:kind, :mount, :detail) }))
    File.write(File.join(directory, 'ready'), '')
    IO.copy_stream(reader, $stdout)
    _, status = Process.wait2(child)
    exit(status.exitstatus || 1) unless status.success?
  ensure
    reader.close
    begin
      Process.kill('TERM', child)
      Process.wait(child)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  end
end
