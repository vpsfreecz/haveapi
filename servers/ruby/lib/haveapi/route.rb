module HaveAPI
  class Route
    attr_reader :path, :sinatra_path, :action, :resource_path

    def initialize(path, action, resource_path)
      @path = path
      @sinatra_path = path.gsub(/:([a-zA-Z\-_]+)/, '{\1}')
      @action = action
      @resource_path = resource_path
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
