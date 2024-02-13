module HaveAPI
  class ExampleList
    def initialize
      @examples = []
    end

    # @param example [Example]
    def <<(example)
      @examples << example
    end

    def describe(context)
      ret = []

      @examples.each do |e|
        ret << e.describe(context) if e.authorized?(context)
      end

      ret
    end

    def each(&)
      @examples.each(&)
    end

    include Enumerable
  end
end
