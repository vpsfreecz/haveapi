module HaveAPI::CLI
  class OutputFormatter
    def self.format(*args)
      f = new(*args)
      f.format
    end

    def self.print(*args)
      f = new(*args)
      f.print
    end

    def initialize(objects, cols = nil, header: true)
      @objects = objects
      @header = header

      if cols
        @cols = parse_cols(cols)

      else
        if @objects.is_a?(::Array) # A list of items
          @cols ||= parse_cols(@objects.first.keys)

        elsif @objects.is_a?(::Hash) # Single item
          @cols ||= parse_cols(@objects.keys)

        else
          fail "unsupported type #{@objects.class}"
        end
      end
    end

    def format
      @out = ''
      generate
      @out
    end

    def print
      @out = nil
      generate
    end

    protected
    def parse_cols(cols)
      ret = []

      cols.each do |c|
        base = {
            align: 'left'
        }

        if c.is_a?(::String) || c.is_a?(::Symbol)
          base.update({
              name: c,
              label: c.to_s.upcase,
          })
          ret << base

        elsif c.is_a?(::Hash)
          base.update(c)
          ret << base

        else
          fail "unsupported column type #{c.class}"
        end
      end

      ret
    end

    def generate
      prepare

      formatters = @cols.map do |c|
        case c[:align].to_sym
        when :right
          "%#{col_width(c)}s"

        else
          "%-#{col_width(c)}s"
        end
      end.join('  ')
      
      line sprintf(formatters, * @cols.map { |c| c[:label] }) if @header

      @str_objects.each do |o|
        line sprintf(formatters, * o.map { |_, v| v.to_s })
      end
    end

    def line(str)
      if @out
        @out += str + "\n"

      else
        puts str
      end
    end

    def prepare
      @str_objects = []
      
      each_object do |o|
        hash = {}
        
        @cols.each do |c|
          v = o[ c[:name] ]

          hash[ c[:name] ] = c[:display] ? c[:display].call(v) : v
        end

        @str_objects << hash
      end

      @str_objects
    end

    def col_width(c)
      w = c[:label].to_s.length
      
      @str_objects.each do |o|
        len = o[ c[:name] ].to_s.length
        w = len if len > w
      end

      w + 1
    end

    def each_object
      if @objects.is_a?(::Array)
        @objects.each { |v| yield(v) }

      else
        yield(@objects)
      end
    end
  end
end
