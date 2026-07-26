require 'date'

module HaveAPI
  class Example
    JSON_SCALARS = [String, Numeric, TrueClass, FalseClass, NilClass].freeze

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

    def validate_build(action, path:, index:)
      return unless provided?
      return unless structured_data_provided?

      @validation_context = "#{action} example #{example_name(index)}"

      validate_path_params(action, path) if path
      validate_payload('request', @request, action.input, require_required: true) unless @request.nil?
      validate_payload('response', @response, action.output, require_required: false) unless @response.nil?
      validate_errors(action.input) unless @errors.nil?
    ensure
      @validation_context = nil
    end

    protected

    def structured_data_provided?
      %i[
        @path_params @request @response @status @message @errors @http_status
      ].any? { |name| !instance_variable_get(name).nil? }
    end

    def example_name(index)
      @title.to_s.empty? ? "##{index + 1}" : @title.inspect
    end

    def validate_path_params(action, path)
      expected = action.path_param_names(path).length
      actual = @path_params.nil? ? 0 : @path_params.length
      return if actual == expected

      invalid!("path_params has #{actual} values, but route #{path.inspect} requires #{expected}")
    end

    def validate_payload(name, value, params, require_required:)
      unless params
        invalid!("#{name} is provided, but the action has no #{name == 'request' ? 'input' : 'output'} parameters")
      end

      objects =
        case params.layout
        when :object, :hash
          invalid!("#{name} must be an object") unless value.is_a?(Hash)
          [value]
        when :object_list, :hash_list
          unless value.is_a?(Array) && value.all?(Hash)
            invalid!("#{name} must be a list of objects")
          end
          value
        else
          invalid!("#{name} uses unsupported layout #{params.layout.inspect}")
        end

      objects.each_with_index do |object, index|
        location = objects.length > 1 ? "#{name}[#{index}]" : name
        validate_object(location, object, params, require_required:)
      end
    end

    def validate_object(location, object, params, require_required:)
      normalized = normalize_keys(location, object)
      known = params.params.to_h { |param| [param.name.to_sym, param] }
      unknown = normalized.keys - known.keys
      invalid!("#{location} contains unknown parameters: #{unknown.join(', ')}") unless unknown.empty?

      if require_required
        missing = known.values.filter_map do |param|
          param.name unless !param.required? || normalized.has_key?(param.name.to_sym)
        end
        invalid!("#{location} is missing required parameters: #{missing.join(', ')}") unless missing.empty?
      end

      normalized.each do |param_name, param_value|
        validate_value("#{location}.#{param_name}", param_value, known.fetch(param_name))
      end
    end

    def normalize_keys(location, object)
      object.each_with_object({}) do |(key, value), ret|
        unless key.is_a?(String) || key.is_a?(Symbol)
          invalid!("#{location} parameter name #{key.inspect} is not a string or symbol")
        end

        normalized = key.to_sym
        invalid!("#{location} repeats parameter #{normalized}") if ret.has_key?(normalized)

        ret[normalized] = value
      end
    end

    def validate_value(location, value, param)
      if value.nil?
        invalid!("#{location} cannot be null") unless param.nullable?
        return
      end

      if param.is_a?(HaveAPI::Parameters::Resource)
        validate_resource_value(location, value, param)
        return
      end

      valid =
        case param.type.to_s
        when 'Integer'
          value.is_a?(Integer)
        when 'Float'
          value.is_a?(Numeric) && value.finite?
        when 'Boolean'
          [true, false].include?(value)
        when 'Datetime'
          valid_datetime?(value)
        when 'String', 'Text'
          value.is_a?(String)
        else
          json_value?(value)
        end

      invalid!("#{location} has invalid #{param.type} value #{value.inspect}") unless valid
    end

    def validate_resource_value(location, value, param)
      return if value.is_a?(Integer) || value.is_a?(String)

      unless value.is_a?(Hash)
        invalid!("#{location} must be a resource ID or object")
      end

      normalized = normalize_keys(location, value)
      id_name = param.value_id.to_sym
      invalid!("#{location} resource object is missing #{id_name}") unless normalized.has_key?(id_name)
      invalid!("#{location}.#{id_name} must be an integer or string") unless [
        Integer,
        String
      ].any? { |klass| normalized.fetch(id_name).is_a?(klass) }
      invalid!("#{location} is not JSON-compatible") unless json_value?(value)
    end

    def valid_datetime?(value)
      return true if value.is_a?(Time) || value.is_a?(DateTime)
      return false unless value.is_a?(String)

      DateTime.iso8601(value)
      true
    rescue ArgumentError
      false
    end

    def json_value?(value)
      return value.finite? if value.is_a?(Float)
      return true if JSON_SCALARS.any? { |klass| value.is_a?(klass) }
      return value.all? { |item| json_value?(item) } if value.is_a?(Array)

      if value.is_a?(Hash)
        return value.all? do |key, item|
          (key.is_a?(String) || key.is_a?(Symbol)) && json_value?(item)
        end
      end

      false
    end

    def validate_errors(input)
      invalid!('errors must be an object') unless @errors.is_a?(Hash)

      known = input ? input.params.map { |param| param.name.to_sym } : []
      unknown = @errors.keys.map(&:to_sym) - known
      invalid!("errors refer to unknown input parameters: #{unknown.join(', ')}") unless unknown.empty?
    end

    def invalid!(message)
      raise "#{@validation_context}: #{message}"
    end

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
