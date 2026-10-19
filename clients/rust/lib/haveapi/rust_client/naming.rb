module HaveAPI::RustClient
  module Naming
    RESERVED = %w[
      as async await break const continue crate dyn else enum extern false fn for if impl in let loop
      match mod move mut pub ref return self Self static struct super trait true type union unsafe use
      where while abstract become box do final macro override priv typeof unsized virtual yield try gen
    ].freeze

    def self.snake(value)
      result = value.to_s.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                    .gsub(/([a-z\d])([A-Z])/, '\1_\2').gsub(/[^a-zA-Z0-9_]/, '_').downcase
      result = "field_#{result}" if result.empty? || result == '_' || result.match?(/\A\d/)
      RESERVED.include?(result) ? "#{result}_" : result
    end

    def self.literal(value)
      escaped = value.to_s.codepoints.map do |char|
        case char
        when 34 then '\"'
        when 92 then '\\\\'
        when 10 then '\n'
        when 13 then '\r'
        when 9 then '\t'
        when 0..31, 127 then "\\u{#{char.to_s(16)}}"
        else char.chr(Encoding::UTF_8)
        end
      end.join
      "\"#{escaped}\""
    end

    class Scope
      def initialize(reserved = [])
        @names = reserved.to_h { |name| [name, "reserved member #{name}"] }
      end

      def add(name, path)
        if @names.has_key?(name)
          raise Error, "Rust name collision #{name}: #{@names[name]} and #{path}"
        end

        @names[name] = path
        name
      end
    end
  end
end
