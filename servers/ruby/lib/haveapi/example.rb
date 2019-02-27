module HaveAPI
  class Example
    def initialize(title)
      @title = title
    end

    def authorize(&block)
      @authorization = block
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

    def authorized?(context)
      if (context.endpoint || context.current_user) \
          && @authorization && !@authorization.call(context.current_user)
        false
      else
        true
      end
    end

    def provided?
      instance_variables.detect do |v|
        instance_variable_get(v)
      end ? true : false
    end

    def describe(context)
      if provided?
        {
            title: @title,
            comment: @comment,
            url_params: @url_params,
            request: filter_input_params(context, @request),
            response: filter_output_params(context, @response),
            status: @status.nil? ? true : @status,
            message: @message,
            errors: @errors,
            http_status: @http_status || 200,
        }
      else
        {}
      end
    end

    protected
    def filter_input_params(context, input)
      case context.action.input.layout
      when :object, :hash
        context.authorization.filter_input(
          context.action.input.params,
          ModelAdapters::Hash.output(context, input),
        )

      when :object_list, :hash_list
        input.map do |obj|
          context.authorization.filter_input(
            context.action.input.params,
            ModelAdapters::Hash.output(context, obj),
            true
          )
        end
      end
    end

    def filter_output_params(context, output)
      case context.action.output.layout
      when :object, :hash
        context.authorization.filter_output(
          context.action.output.params,
          ModelAdapters::Hash.output(context, output),
          true
        )

      when :object_list, :hash_list
        output.map do |obj|
          context.authorization.filter_output(
            context.action.output.params,
            ModelAdapters::Hash.output(context, obj),
            true
          )
        end
      end
    end
  end
end
