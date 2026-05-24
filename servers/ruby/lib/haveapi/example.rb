module HaveAPI
  class Example
    def initialize(title)
      @title = title
    end

    def authorize(&block)
      @authorization = block
    end

    def path_params(*params)
      @path_params = params
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
      return true unless @authorization
      return true unless context.current_user

      @authorization.call(context.current_user) ? true : false
    end

    def provided?
      instance_variables.any? do |v|
        value = instance_variable_get(v)
        next false if v == :@title && value.to_s.empty?

        !value.nil? && value != false
      end
    end

    def describe(context)
      if provided?
        {
          title: @title,
          comment: @comment,
          path_params: @path_params,
          request: @request.nil? ? nil : filter_input_params(context, @request),
          response: @response.nil? ? nil : filter_output_params(context, @response),
          status: @status.nil? ? true : @status,
          message: @message,
          errors: @errors,
          http_status: @http_status || 200
        }
      else
        {}
      end
    end

    protected

    def filter_input_params(context, input)
      return nil if input.nil?

      case context.action.input.layout
      when :object, :hash
        context.authorization.filter_input(
          context.action.input.params,
          ModelAdapters::Hash.output(context, input)
        )

      when :object_list, :hash_list
        input.map do |obj|
          context.authorization.filter_input(
            context.action.input.params,
            ModelAdapters::Hash.output(context, obj)
          )
        end
      end
    end

    def filter_output_params(context, output)
      return nil if output.nil?

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
