module HaveAPI::OutputFormatters
  class BaseFormatter
    class << self
      attr_reader :types

      def handle(*args)
        @types ||= []
        @types += args

        HaveAPI::OutputFormatter.register(Kernel.const_get(self.to_s)) unless @registered
        @registered = true
      end

      def handle?(type)
        @types.detect do |t|
           File.fnmatch(type, t)
        end
      end
    end

    def content_type
      self.class.types.first
    end

    def format(response)

    end
  end
end
