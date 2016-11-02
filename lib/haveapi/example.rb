module HaveAPI
  class Example
    def initialize(title)
      @title = title
    end

    def url_params(*params)
      @url_params = params
    end

    def request(f)
      @request = f
    end

    def response(f)
      @response = f
    end

    def comment(str)
      @comment = str
    end

    def provided?
      @request || @response || @comment
    end

    def describe
      if provided?
        {
            title: @title,
            url_params: @url_params,
            request: @request,
            response: @response,
            comment: @comment
        }
      else
        {}
      end
    end
  end
end
