require 'cgi'
require 'json'

module HaveAPI
  # Presents already-authorized/localized metadata without changing validation.
  class DocumentationValidators
    def self.render(validators, type: nil)
      return '' if validators.nil? || validators == {}
      return new(type).data(validators) unless validators.is_a?(Hash)

      renderer = new(type)
      rules = validators.map { |name, options| renderer.rule(name, options) }.join
      %(<div class="docs-validators"><table class="docs-validator-table"><caption>Validation rules</caption><thead><tr><th scope="col">Rule</th><th scope="col">Details</th></tr></thead><tbody>#{rules}</tbody></table></div>)
    end

    def initialize(type)
      @type = type
    end

    def rule(name, options)
      content, used = explanation(name.to_s, options)
      if content && options.is_a?(Hash)
        remaining = options.reject { |key, _| used.include?(key.to_s) || key.to_s == 'message' }
        content += "<p><strong>Validation error message:</strong> #{value(field(options, :message))}</p>" if option?(options, :message)
        unless remaining.empty?
          content += "<details><summary>Additional details</summary>#{data(remaining)}</details>"
        end
      elsif !content
        content = "<p>Supplied validator metadata:</p>#{data(options)}"
      end
      known = %w[present include exclude accept confirm number length format custom].include?(name.to_s)
      title = known ? name.to_s.capitalize : name.to_s
      %(<tr class="docs-validator"><th scope="row">#{html(title)}</th><td>#{content}</td></tr>)
    end

    def explanation(name, options)
      return ["<p>Application-specific rule: #{html(options)}</p>", []] if name == 'custom' && options.is_a?(String)
      return unless options.is_a?(Hash)
      # Two differently typed keys must not silently collapse to one option.
      return if options.keys.map(&:to_s).uniq.length != options.length

      case name
      when 'present' then presence(options)
      when 'include', 'exclude' then choices(name, options)
      when 'accept'
        return unless option?(options, :value)

        ["<p>Must equal #{literal(field(options, :value))}.</p>", ['value']]
      when 'confirm'
        return unless field(options, :parameter).is_a?(String) || field(options, :parameter).is_a?(Symbol)
        return unless boolean?(field(options, :equal))

        relation = field(options, :equal) ? 'Must equal' : 'Must differ from'
        ["<p>#{relation} parameter <code>#{html(field(options, :parameter))}</code>.</p>", %w[parameter equal]]
      when 'number' then number(options)
      when 'length' then length(options)
      when 'format'
        return unless field(options, :rx).is_a?(String) && boolean?(field(options, :match))

        relation = field(options, :match) ? 'Must match' : 'Must not match'
        content = "<p>#{relation} this regular expression:</p><pre><code>#{html(field(options, :rx))}</code></pre>"
        content += "<p>#{value(field(options, :description))}</p>" if option?(options, :description)
        [content, %w[rx match description]]
      end
    end

    def presence(options)
      return unless boolean?(field(options, :empty))

      empty = field(options, :empty) ? 'Empty values are allowed.' : 'Must not be empty; strings must contain a non-whitespace character.'
      ["<p>Must be supplied and cannot be null. #{empty}</p>", ['empty']]
    end

    def choices(name, options)
      values = field(options, :values)
      return unless values.is_a?(Array) || (name == 'include' && values.is_a?(Hash))

      label = name == 'include' ? 'Allowed values' : 'Disallowed values'
      items = if values.is_a?(Hash)
                values.map { |machine, label_text| "<li>#{literal(machine)}: #{value(label_text)}</li>" }
              else
                values.map { |machine| "<li>#{literal(machine)}</li>" }
              end
      body = items.empty? ? '<p>The set is empty.</p>' : %(<ul class="docs-validator-values">#{items.join}</ul>)
      ["<p>#{label}:</p>#{body}", ['values']]
    end

    def number(options)
      numeric = %w[min max step mod]
      return unless numeric.all? { |key| !option?(options, key) || finite_number?(field(options, key)) }
      return unless %w[odd even].all? { |key| !option?(options, key) || boolean?(field(options, key)) }

      lines = ['Must be a number after parameter type conversion.']
      lines << "Minimum: #{literal(field(options, :min))} (inclusive)." if option?(options, :min)
      lines << "Maximum: #{literal(field(options, :max))} (inclusive)." if option?(options, :max)
      if option?(options, :step)
        start = option?(options, :min) ? field(options, :min) : 0
        lines << "Step: #{literal(field(options, :step))}, measured from #{literal(start)}."
      end
      lines << "Must be a multiple of #{literal(field(options, :mod))}, measured from zero." if option?(options, :mod)
      lines << 'Must be odd.' if field(options, :odd) == true
      lines << 'Must be even.' if field(options, :even) == true
      lines << 'Odd-only restriction: disabled.' if option?(options, :odd) && field(options, :odd) == false
      lines << 'Even-only restriction: disabled.' if option?(options, :even) && field(options, :even) == false
      ["<ul>#{lines.map { |line| "<li>#{line}</li>" }.join}</ul>", numeric + %w[odd even]]
    end

    def length(options)
      keys = %w[equals min max]
      return unless keys.any? { |key| option?(options, key) }
      return unless keys.all? { |key| !option?(options, key) || field(options, key).is_a?(Integer) }
      return if option?(options, :equals) && (option?(options, :min) || option?(options, :max))

      unit = if %w[String Text].include?(@type)
               ' characters'
             elsif %w[List Array].include?(@type)
               ' items'
             else
               ''
             end
      lines = []
      lines << "Length must equal #{literal(field(options, :equals))}#{unit}." if option?(options, :equals)
      lines << "Minimum length: #{literal(field(options, :min))}#{unit} (inclusive)." if option?(options, :min)
      lines << "Maximum length: #{literal(field(options, :max))}#{unit} (inclusive)." if option?(options, :max)
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
      json_value?(value) ? "<code>#{html(JSON.generate(value))}</code>" : "<span>Ruby value: <code>#{html(value.inspect)}</code></span>"
    end

    def value(value)
      value.is_a?(String) ? html(value) : literal(value)
    end

    def data(value)
      label, text = if json_value?(value)
                      ['JSON', JSON.pretty_generate(value)]
                    else
                      ['Ruby value', value.inspect]
                    end
      "<p>#{label}:</p><pre><code>#{html(text)}</code></pre>"
    end

    def html(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
