module HaveAPI
  class Route
    attr_reader :path, :action

    def initialize(path, action)
      @path = path
      @action = action
    end

    def http_method
      @action.http_method
    end

    def description
      @action.desc
    end

    def params
      @action.params
    end
  end
end
