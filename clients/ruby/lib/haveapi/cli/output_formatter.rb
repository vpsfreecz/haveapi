module HaveAPI::CLI
  class OutputFormatter
    def self.format(*)
      f = new(*)
      f.format
    end

    def self.print(*, **)
      f = new(*, **)
      f.print
    end

    def initialize(objects, cols = nil, header: true, sort: nil, layout: nil, empty: '-')
      @objects = objects
      @header = header
      @sort = sort
      @layout = layout
      @empty = empty

      if @layout.nil?
        @layout = if many?
                    :columns

                  else
                    :rows
                  end
      end

      if cols
        @cols = parse_cols(cols)

      elsif @objects.is_a?(::Array)
        @cols ||= parse_cols(@objects.first.keys) # A list of items

      elsif @objects.is_a?(::Hash) # Single item
        @cols ||= parse_cols(@objects.keys)

      else
        raise "unsupported type #{@objects.class}"
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
              label: c.to_s.upcase
          })
          ret << base

        elsif c.is_a?(::Hash)
          base.update(c)
          ret << base

        else
          raise "unsupported column type #{c.class}"
        end
      end

      ret
    end

    def generate
      return if @cols.empty?

      prepare

      case @layout
      when :columns
        columns

      when :rows
        rows

      else
        raise "unsupported layout '#{@layout}'"
      end
    end

    # Each object is printed on one line, it's parameters aligned into columns.
    def columns
      i = 0

      formatters = @cols.map do |c|
        ret = case c[:align].to_sym
              when :right
                "%#{col_width(i, c)}s"

              else
                "%-#{col_width(i, c)}s"
              end

        i += 1
        ret
      end.join('  ')

      line format(formatters, * @cols.map { |c| c[:label] }) if @header

      @str_objects.each do |o|
        line format(formatters, *o)
      end
    end

    # Each object is printed on multiple lines, one parameter per line.
    def rows
      w = heading_width

      @str_objects.each do |o|
        @cols.each_index do |i|
          c = @cols[i]

          if o[i].is_a?(::String) && o[i].index("\n")
            lines = o[i].split("\n")
            v = ([lines.first] + lines[1..].map { |l| (' ' * (w + 3)) + l }).join("\n")

          else
            v = o[i]
          end

          # rubocop:disable Lint/FormatParameterMismatch
          line format("%#{w}s:  %s", c[:label], v)
          # rubocop:enable Lint/FormatParameterMismatch
        end

        line
      end
    end

    def line(str = '')
      if @out
        @out += "#{str}\n"

      else
        puts str
      end
    end

    def prepare
      @str_objects = []

      each_object do |o|
        arr = []

        @cols.each do |c|
          v = o[c[:name]]
          str = (c[:display] ? c[:display].call(v) : v)
          str = @empty if !str || (str.is_a?(::String) && str.empty?)

          arr << str
        end

        @str_objects << arr
      end

      if @sort
        col_i = @cols.index { |c| c[:name] == @sort }
        raise "unknown column '#{@sort}'" unless col_i

        @str_objects.sort! do |a, b|
          a_i = a[col_i]
          b_i = b[col_i]

          next 0 if a_i == @empty && b_i == @empty
          next -1 if a_i == @empty && b_i != @empty
          next 1 if a_i != @empty && b_i == @empty

          a_i <=> b_i
        end
      end

      @str_objects
    end

    def col_width(i, c)
      w = c[:label].to_s.length

      @str_objects.each do |o|
        len = o[i].to_s.length
        w = len if len > w
      end

      w + 1
    end

    def heading_width
      w = @cols.first[:label].to_s.length

      @cols.each do |c|
        len = c[:label].to_s.length

        w = len if len > w
      end

      w + 1
    end

    def each_object(&)
      if @objects.is_a?(::Array)
        @objects.each(&)

      else
        yield(@objects)
      end
    end

    def many?
      @objects.is_a?(::Array) && @objects.size > 1
    end
  end
end
