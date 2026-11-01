require 'cgi'
require 'json'
require 'haveapi/i18n'

module HaveAPI
  # Presents already-authorized/localized metadata without changing validation.
  class DocumentationValidators
    def self.render(validators, type: nil)
      return '' if validators.nil? || validators == {}
      return new(type).data(validators) unless validators.is_a?(Hash)

      renderer = new(type)
      rules = validators.map { |name, options| renderer.rule(name, options) }.join
      %(<div class="docs-validators"><table class="docs-validator-table"><caption>#{renderer.text('caption')}</caption><thead><tr><th scope="col">#{renderer.text('rule')}</th><th scope="col">#{renderer.text('details')}</th></tr></thead><tbody>#{rules}</tbody></table></div>)
    end

    def initialize(type)
      @type = type
    end

    # Escape catalog text before interpolating markup produced by this renderer.
    # Validator metadata is always escaped by value/literal/html first.
    def text(key, **values)
      full_key = "haveapi.documentation.validators.#{key}"
      fallback = ::I18n.t(full_key, locale: :en, skip_interpolation: true)
      template = ::I18n.t(full_key, default: fallback, skip_interpolation: true)
      format(html(template), **values)
    end

    def rule(name, options)
      content, used = explanation(name.to_s, options)
      if content && options.is_a?(Hash)
        remaining = options.reject { |key, _| used.include?(key.to_s) || key.to_s == 'message' }
        content += "<p><strong>#{text('message')}</strong> #{value(field(options, :message))}</p>" if option?(options, :message)
        unless remaining.empty?
          content += "<details><summary>#{text('additional')}</summary>#{data(remaining)}</details>"
        end
      elsif !content
        content = "<p>#{text('metadata')}</p>#{data(options)}"
      end
      known = %w[present include exclude accept confirm number length format custom].include?(name.to_s)
      title = known ? text("names.#{name}") : html(name)
      %(<tr class="docs-validator"><th scope="row">#{title}</th><td>#{content}</td></tr>)
    end

    def explanation(name, options)
      return ["<p>#{text('custom', rule: html(options))}</p>", []] if name == 'custom' && options.is_a?(String)
      return unless options.is_a?(Hash)
      # Two differently typed keys must not silently collapse to one option.
      return if options.keys.map(&:to_s).uniq.length != options.length

      case name
      when 'present' then presence(options)
      when 'include', 'exclude' then choices(name, options)
      when 'accept'
        return unless option?(options, :value)

        ["<p>#{text('accept', value: literal(field(options, :value)))}</p>", ['value']]
      when 'confirm'
        return unless field(options, :parameter).is_a?(String) || field(options, :parameter).is_a?(Symbol)
        return unless boolean?(field(options, :equal))

        relation = field(options, :equal) ? 'confirm_equal' : 'confirm_different'
        ["<p>#{text(relation, parameter: "<code>#{html(field(options, :parameter))}</code>")}</p>", %w[parameter equal]]
      when 'number' then number(options)
      when 'length' then length(options)
      when 'format'
        return unless field(options, :rx).is_a?(String) && boolean?(field(options, :match))

        relation = field(options, :match) ? 'format_match' : 'format_no_match'
        content = "<p>#{text(relation)}</p><pre><code>#{html(field(options, :rx))}</code></pre>"
        content += "<p>#{value(field(options, :description))}</p>" if option?(options, :description)
        [content, %w[rx match description]]
      end
    end

    def presence(options)
      return unless boolean?(field(options, :empty))

      empty = field(options, :empty) ? 'empty_allowed' : 'empty_disallowed'
      ["<p>#{text('present')} #{text(empty)}</p>", ['empty']]
    end

    def choices(name, options)
      values = field(options, :values)
      return unless values.is_a?(Array) || (name == 'include' && values.is_a?(Hash))

      label = name == 'include' ? 'allowed' : 'disallowed'
      items = if values.is_a?(Hash)
                values.map { |machine, label_text| "<li>#{choice_literal(machine)}: #{value(label_text)}</li>" }
              else
                values.map { |machine| "<li>#{choice_literal(machine)}</li>" }
              end
      body = items.empty? ? "<p>#{text('empty_set')}</p>" : %(<ul class="docs-validator-values">#{items.join}</ul>)
      ["<p>#{text(label)}:</p>#{body}", ['values']]
    end

    def number(options)
      numeric = %w[min max step mod]
      return unless numeric.all? { |key| !option?(options, key) || finite_number?(field(options, key)) }
      return unless %w[odd even].all? { |key| !option?(options, key) || boolean?(field(options, key)) }

      lines = [text('number')]
      lines << text('minimum', value: literal(field(options, :min))) if option?(options, :min)
      lines << text('maximum', value: literal(field(options, :max))) if option?(options, :max)
      if option?(options, :step)
        start = option?(options, :min) ? field(options, :min) : 0
        lines << text('step', value: literal(field(options, :step)), start: literal(start))
      end
      lines << text('multiple', value: literal(field(options, :mod))) if option?(options, :mod)
      lines << text('odd') if field(options, :odd) == true
      lines << text('even') if field(options, :even) == true
      lines << text('odd_disabled') if option?(options, :odd) && field(options, :odd) == false
      lines << text('even_disabled') if option?(options, :even) && field(options, :even) == false
      ["<ul>#{lines.map { |line| "<li>#{line}</li>" }.join}</ul>", numeric + %w[odd even]]
    end

    def length(options)
      keys = %w[equals min max]
      return unless keys.any? { |key| option?(options, key) }
      return unless keys.all? { |key| !option?(options, key) || field(options, key).is_a?(Integer) }
      return if option?(options, :equals) && (option?(options, :min) || option?(options, :max))

      unit = if %w[String Text].include?(@type)
               text('characters')
             elsif %w[List Array].include?(@type)
               text('items')
             else
               ''
             end
      lines = []
      lines << text('length_equal', value: literal(field(options, :equals)), unit:) if option?(options, :equals)
      lines << text('length_minimum', value: literal(field(options, :min)), unit:) if option?(options, :min)
      lines << text('length_maximum', value: literal(field(options, :max)), unit:) if option?(options, :max)
      ["<ul>#{lines.map { |line| "<li>#{line}</li>" }.join}</ul>", keys]
    end

    def option?(options, name)
      options.has_key?(name.to_sym) || options.has_key?(name.to_s)
    end

    def field(options, name)
      options.has_key?(name.to_sym) ? options[name.to_sym] : options[name.to_s]
    end

    def boolean?(value)
      [true, false].include?(value)
    end

    def finite_number?(value)
      value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
    end

    def json_value?(value)
      case value
      when String, Integer, true, false, nil then true
      when Float then value.finite?
      when Array then value.all? { |item| json_value?(item) }
      when Hash then value.all? { |key, item| key.is_a?(String) && json_value?(item) }
      else false
      end
    end

    def literal(value)
      json_value?(value) ? "<code>#{html(JSON.generate(value))}</code>" : "<span>#{text('ruby_value')}: <code>#{html(value.inspect)}</code></span>"
    end

    def choice_literal(value)
      value.is_a?(String) ? "<code>#{html(value)}</code>" : literal(value)
    end

    def value(value)
      value.is_a?(String) ? html(value) : literal(value)
    end

    def data(value)
      label, text = if json_value?(value)
                      ['JSON', JSON.pretty_generate(value)]
                    else
                      [text('ruby_value'), value.inspect]
                    end
      "<p>#{label}:</p><pre><code>#{html(text)}</code></pre>"
    end

    def html(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
