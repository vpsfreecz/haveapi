module HaveAPI::Extensions
  class ActionExceptions < Base
    class << self
      def enabled
        HaveAPI::Action.connect_hook(:exec_exception) do |ret, action, e|
          break(ret) unless @exceptions

          @exceptions.each do |handler|
            if e.is_a?(handler[:klass])
              ret = handler[:block].call(ret, e)
              break
            end
          end

          ret
        end
      end

      def rescue(klass, &block)
        @exceptions ||= []
        @exceptions << {klass: klass, block: block}
      end
    end
  end
end
