module HaveAPI
  module OutputFormatters
  end

  class OutputFormatter
    class << self
      attr_reader :formatters

      def register(klass)
        @formatters ||= []
        @formatters << klass
      end
    end

    def supports?(types)
      @formatter = nil

      if types.empty?
        return @formatter = self.class.formatters.first.new
      end

      types.each do |type|
        self.class.formatters.each do |f|
          if f.handle?(type)
            @formatter = f.new
            break
          end
        end
      end

      !@formatter.nil?
    end

    def format(status, response, message = nil, errors = nil, version: true)
      @formatter.format(header(status, response, message, errors, version))
    end

    def error(msg)
      @formatter.format(header(false, nil, msg))
    end

    def content_type
      @formatter.content_type
    end

    protected

    def header(status, response, message = nil, errors = nil, version)
      ret = {}
      ret[:version] = HaveAPI::PROTOCOL_VERSION if version
      ret.update({
        status:,
        response:,
        message:,
        errors:
      })
      ret
    end
  end
end
