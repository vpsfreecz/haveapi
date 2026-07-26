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

    def validate_build(action, path:)
      @examples.each_with_index do |example, index|
        example.validate_build(action, path:, index:)
      end
    end

    def each(&)
      @examples.each(&)
    end

    include Enumerable
  end
end
