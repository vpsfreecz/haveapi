# Test only the authored prose emission boundary. No parsing or stripping of
# source literals, transcript data or commented commands takes place here.
module ExampleCommentCapture
  def comment_capture_class(base)
    emissions = []
    captured = Class.new(base) do
      define_method(:comment_lines) do |text, prefix|
        block = super(text, prefix)
        marker = "__HAVEAPI_COMMENT_EMISSION_#{emissions.length}__"
        emissions << { marker:, block:, prefix: }
        marker
      end
    end
    [captured, emissions]
  end

  def restore_comment_emissions(template, emissions)
    restored = template.dup
    emissions.each do |emission|
      marker = emission.fetch(:marker)
      count = restored.scan(marker).length
      next if count == 0 # Some renderers prepare a fragment before selecting another branch.

      expect(count).to eq(1)
      offset = restored.index(marker)
      line_start = restored.rindex("\n", offset) || -1
      indentation = restored[(line_start + 1)...offset]
      indentation = '' unless indentation.match?(/\A[ \t]*\z/)
      restored = restored.sub(marker) { emission.fetch(:block).gsub("\n", "\n#{indentation}") }
    end
    restored
  end
end

module ExampleCommentCapture
  # Standalone adapters consume a duck-typed context and need no server gem.
  def localized_comment_context(context, locale)
    require 'yaml'
    catalog = YAML.load_file(File.expand_path('../../../../i18n/haveapi.yml', __dir__))
                  .fetch(locale.to_s).fetch('haveapi').fetch('documentation')
    localized = context.dup
    localized.define_singleton_method(:documentation_message) do |key, default:, **values|
      message = key.split('.').reduce(catalog) { |tree, part| tree.is_a?(Hash) ? tree[part] : nil } || default
      values.empty? ? message : format(message, values)
    end
    localized.define_singleton_method(:example_comment) do |key, default:, **values|
      documentation_message("comments.#{key}", default:, **values)
    end
    localized
  end

  def expect_adapter_comment_parity(base, context, **arguments, &factory)
    actual = []
    templates = []
    traces = []
    %i[en cs].each do |locale|
      localized = localized_comment_context(context, locale)
      rendered = factory.call(base).freeze.render(context: localized, **arguments)
      expect(rendered[:status]).to eq(:code), "#{arguments.inspect}: #{rendered.inspect}"
      actual << rendered.fetch(:code)
      capture, emissions = comment_capture_class(base)
      templates << factory.call(capture).freeze.render(context: localized, **arguments).fetch(:code)
      traces << emissions
      expect(restore_comment_emissions(templates.last, emissions)).to eq(actual.last)
    end
    expect(templates[1]).to eq(templates[0])
    expect(traces[1].map { |item| item[:prefix] }).to eq(traces[0].map { |item| item[:prefix] })
    # The same adapter used with an old context retains the original English.
    expect(factory.call(base).freeze.render(context:, **arguments).fetch(:code)).to eq(actual[0])
    actual
  end
end
