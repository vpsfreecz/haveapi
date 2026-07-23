require 'digest/sha1'
require 'json'

module HaveAPI::GoClient
  module Utils
    GO_KEYWORDS = %w[
      break case chan const continue default defer else fallthrough for func go
      goto if import interface map package range return select struct switch type
      var
    ].freeze

    # Remove underscores and capitalize names
    # @param v [String]
    # @return [String]
    def camelize(v)
      raw = v.to_s
      current = raw.split('_').map(&:capitalize).join
      sanitized = raw.gsub(/[^A-Za-z0-9_]/, '_')
      candidate = sanitized.split('_').reject(&:empty?).map(&:capitalize).join
      candidate = 'X' if candidate.empty?
      candidate = "X#{candidate}" unless go_identifier?(candidate)

      if candidate != current || go_keyword?(candidate)
        "#{candidate}_#{identifier_hash(raw)}"
      else
        candidate
      end
    end

    # @param v [String]
    # @return [String]
    def safe_file_component(v)
      raw = v.to_s
      candidate = raw.gsub(/[^A-Za-z0-9_-]/, '_')
      candidate = 'x' if candidate.empty?

      if candidate != raw || %w[. ..].include?(candidate)
        "#{candidate}_#{identifier_hash(raw)}"
      else
        candidate
      end
    end

    # Add the .go suffix without accidentally creating a Go test source file.
    # Generated resources and actions are package code, even when their API
    # name is "test".
    def go_source_filename(v)
      base = v.to_s
      base = "#{base}_#{identifier_hash(base)}" if base.end_with?('_test')
      "#{base}.go"
    end

    # @param v [String]
    # @return [String]
    def go_package_name(v)
      raw = v.to_s
      candidate = raw.gsub(/[^A-Za-z0-9_]/, '_')
      candidate = 'pkg' if candidate.empty? || candidate == '_'
      candidate = "pkg_#{candidate}" unless go_identifier?(candidate)

      if candidate != raw || go_keyword?(candidate)
        "#{candidate}_#{identifier_hash(raw)}"
      else
        candidate
      end
    end

    # @param v [String]
    # @return [String]
    def go_module_path(v)
      raw = v.to_s

      if raw.empty? || raw.match?(/[\s[:cntrl:]]/)
        raise ArgumentError, "invalid Go module path '#{raw}'"
      end

      raw
    end

    # @param v [String]
    # @return [String]
    def go_string_literal(v)
      JSON.generate(v.to_s)
    end

    # @param v [String]
    # @return [String]
    def go_json_tag(v)
      go_string_literal("json:#{JSON.generate(v.to_s)}")
    end

    # @param namespace [String]
    # @param name [String]
    # @return [String]
    def go_query_key(namespace, name)
      go_string_literal("#{namespace}[#{name}]")
    end

    # @param v [String]
    # @return [String]
    def go_comment_text(v)
      v.to_s.gsub(/[\r\n\t]+/, ' ').gsub(/[[:cntrl:]]+/, ' ').strip
    end

    protected

    def go_identifier?(v)
      v.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
    end

    def go_keyword?(v)
      GO_KEYWORDS.include?(v)
    end

    def identifier_hash(v)
      Digest::SHA1.hexdigest(v.to_s)[0, 8]
    end
  end
end
