module HaveAPI
  class Route
    attr_reader :path, :sinatra_path, :action

    def initialize(path, action)
      @path = path
      @sinatra_path = path.gsub(/:([a-zA-Z\-_]+)/, '{\1}')
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
