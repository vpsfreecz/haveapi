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

    def status(status)
      @status = status
    end

    def message(msg)
      @message = msg
    end

    def errors(errs)
      @errors = errs
    end

    def http_status(code)
      @http_status = code
    end

    def comment(str)
      @comment = str
    end

    def provided?
      instance_variables.detect do |v|
        instance_variable_get(v)
      end ? true : false
    end

    def describe
      if provided?
        {
            title: @title,
            comment: @comment,
            url_params: @url_params,
            request: @request,
            response: @response,
            status: @status.nil? ? true : @status,
            message: @message,
            errors: @errors,
            http_status: @http_status || 200,
        }
      else
        {}
      end
    end
  end
end
