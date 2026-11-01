require 'spec_helper'
require 'ripper'
require 'open3'
require 'tempfile'
require_relative 'dynamic_fixture'
require_relative 'comment_capture'

RSpec.describe HaveAPI::ClientExample do
  include DynamicExampleFixture
  include ExampleCommentCapture

  let(:renderers) do
    described_class.clients.reject { |renderer| %w[go rust typescript-generated].include?(renderer.code.to_s) }
  end

  def render_comments(renderer, context, kind, method = nil)
    renderer.render(kind, context:, auth_method: method, auth_description: token_description.merge(
      authorize_path: '/authorize', token_path: '/token', http_header: 'X-Token'
    )).fetch(:code)
  end

  def context_for_comments(detail)
    dynamic_context(detail:, resource_path: ['widget'], action_name: 'show',
                    action: dynamic_action.merge(blocking: true),
                    sample: dynamic_sample.merge(path_params: [], request: { name: 'literal // # komentář', enabled: false,
                                                                             count: 0, nullable: nil }))
  end

  it 'varies only authored prose boundaries across all native renderers, kinds and detail levels' do
    differences = 0
    renderers.each do |renderer|
      %i[simple thorough].each do |detail|
        [[:init, nil], %i[auth basic], %i[auth token], %i[auth oauth2], [:example, nil]].each do |kind, method|
          context = context_for_comments(detail)
          # HTTP needs sample status metadata; action outputs remain literal data.
          context = context.with(sample: context.sample.merge(http_status: 200))
          actual = []
          traced = []
          traces = []
          %i[en cs].each do |locale|
            localized = context.with(locale:)
            result = renderer.render(kind, context: localized, auth_method: method, auth_description: token_description.merge(
              authorize_path: '/authorize', token_path: '/token', http_header: 'X-Token'
            ))
            next unless result[:status] == :code

            actual << result.fetch(:code)
            capture, emissions = comment_capture_class(renderer)
            traced << render_comments(capture, localized, kind, method)
            traces << emissions
            expect(restore_comment_emissions(traced.last, emissions)).to eq(actual.last)
          end
          next if actual.empty?

          expect(actual.length).to eq(2)
          expect(traced[1]).to eq(traced[0]), "Noncomment source changed for #{renderer} #{kind}/#{method}/#{detail}"
          expect(traces[1].map { |item| item[:prefix] }).to eq(traces[0].map { |item| item[:prefix] })
          differences += 1 if actual[0] != actual[1]
        end
      end
    end
    expect(differences).to be > 20
  end

  it 'preserves response data and failure semantics across every Ruby and PHP layout' do
    [HaveAPI::ClientExamples::RubyClient, HaveAPI::ClientExamples::PhpClient].each do |renderer|
      %i[hash hash_list object object_list].product([true, false]).each do |layout, success|
        context = context_for_comments(:simple)
        output = { layout:, namespace: :widget, parameters: {
          name: { type: 'String' }, custom: { type: 'Custom' },
          relation: { type: 'Resource', resource: ['owner'] }
        } }
        response = { name: 'literal // # komentář', custom: false, relation: { id: 0 } }
        response = [response] if %i[hash_list object_list].include?(layout)
        context = context.with(action: context.action.merge(output:), sample: context.sample.merge(status: success, response:))
        templates = []
        %i[en cs].each do |locale|
          localized = context.with(locale:)
          actual = renderer.render(:example, context: localized).fetch(:code)
          capture, emissions = comment_capture_class(renderer)
          templates << capture.render(:example, context: localized).fetch(:code)
          expect(restore_comment_emissions(templates.last, emissions)).to eq(actual)
        end
        expect(templates[1]).to eq(templates[0])
      end
    end
  end

  it 'translates Ruby token reuse and leaves direct legacy renderer calls English' do
    context = context_for_comments(:simple)
    renderer = HaveAPI::ClientExamples::RubyClient
    czech = render_comments(renderer, context.with(locale: :cs), :auth, :token)
    english = render_comments(renderer, context, :auth, :token)
    expect(czech).to include(::I18n.t('haveapi.documentation.comments.reuse_token', locale: :cs))
    expect(czech).not_to include('# Reuse an existing token')
    direct = renderer.new(context.host, context.base_url, context.version).auth(:token, token_description)
    expect(direct).to include('# Reuse an existing token')
    [english, czech].each { |source| expect(Ripper.sexp(source)).not_to be_nil }
  end

  it 'keeps Czech comments syntactically inert in native programs and async fragments' do
    renderers.select { |renderer| %i[ruby php javascript typescript python].include?(renderer.code) }.each do |renderer|
      %i[simple thorough].each do |detail|
        [[:init, nil], %i[auth token], %i[auth oauth2], [:example, nil]].each do |kind, method|
          context = context_for_comments(detail).with(locale: :cs)
          result = renderer.render(kind, context:, auth_method: method, auth_description: token_description)
          next unless result[:status] == :code

          source = result.fetch(:code)
          case renderer.code
          when :ruby
            expect(Ripper.sexp(source)).not_to be_nil
          when :php
            output, status = Open3.capture2e('php', '-l', stdin_data: "<?php\n#{source}")
            expect(status).to be_success, output
          when :javascript
            Tempfile.create(['haveapi-comment-', '.mjs']) do |file|
              file.write(source)
              file.flush
              output, status = Open3.capture2e('node', '--check', file.path)
              expect(status).to be_success, output
            end
          when :python
            if kind == :example && detail == :simple && renderer == HaveAPI::ClientExamples::PythonAsyncClient
              source = "async def example():\n#{source.lines.map { |line| "    #{line}" }.join}"
            end
            output, status = Open3.capture2e('python', '-c', 'import ast, sys; ast.parse(sys.stdin.read())', stdin_data: source)
            expect(status).to be_success, output
          when :typescript
            compiler = File.expand_path('../../../../clients/js/node_modules/typescript', __dir__)
            script = 'const ts = require(process.argv[1]); let src = ""; process.stdin.on("data", x => src += x); process.stdin.on("end", () => { const result = ts.transpileModule(src, { reportDiagnostics: true, compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }); if ((result.diagnostics || []).length) { process.stderr.write(JSON.stringify(result.diagnostics)); process.exitCode = 1; } });'
            output, status = Open3.capture2e('node', '-e', script, compiler, stdin_data: source)
            expect(status).to be_success, output
          end
        end
      end
    end
  end

  it 'keeps interpolated multiline translations inside actual Ruby comment tokens' do
    localized_context = Class.new(HaveAPI::ClientExample::Context) do
      def example_comment(*)
        "first\r\nputs(:unexpected)\nlast"
      end
    end
    context = context_for_comments(:simple)
    localized = localized_context.new(**HaveAPI::ClientExample::Context::FIELDS.to_h { |field| [field, context.public_send(field)] })
    source = render_comments(HaveAPI::ClientExamples::RubyClient, localized, :auth, :token)
    expect(source).to include("# first\n# puts(:unexpected)\n# last")
    tokens = Ripper.lex(source)
    expect(tokens.reject { |(_, type, _, _)| type == :on_comment }.map { |(_, _, token, _)| token }.join)
      .not_to include('unexpected')
    expect(Ripper.sexp(source)).not_to be_nil
  end

  it 'prefixes every physical translated prose line, including interpolated newlines' do
    renderer = HaveAPI::ClientExamples::RubyClient.new('api.test', '/', '1')
    expect(renderer.comment_lines("first\r\nsecond\rthird\n", '  # ')).to eq("  # first\n  # second\n  # third\n  # ")
    expect(renderer.comment_lines("first\nsecond", '    // ')).to eq("    // first\n    // second")
    expect(renderer.example_comment('missing', default: 'Type %{value}', value: "A\nB")).to eq("Type A\nB")
  end
end
