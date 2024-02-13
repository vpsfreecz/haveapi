require 'haveapi/go_client/utils'

module HaveAPI::GoClient
  class Action
    include Utils

    # @return [Resource]
    attr_reader :resource

    # Name as returned by the API
    # @return [String]
    attr_reader :name

    # Name aliases as returned by the API
    # @return [Array<String>]
    attr_reader :aliases

    # Full action name, including resource
    # @return [String]
    attr_reader :full_dot_name

    # Name for usage in Go
    # @return [String]
    attr_reader :go_name

    # Data type for Go
    # @return [String]
    attr_reader :go_type

    # @return [Metadata]
    attr_reader :metadata

    # @return [InputOutput]
    attr_reader :input

    # @return [InputOutput]
    attr_reader :output

    # @return [String]
    attr_reader :http_method

    # @return [String]
    attr_reader :path

    # Go type for invocation struct
    # @return [String]
    attr_reader :go_invocation_type

    # Go type for request struct
    # @return [String]
    attr_reader :go_request_type

    # Go type for response struct
    # @return [String]
    attr_reader :go_response_type

    def initialize(resource, name, desc, prefix: nil)
      @resource = resource
      @name = name.to_s
      @prefix = prefix
      @aliases = desc[:aliases]
      @full_dot_name = "#{resource.full_dot_name}##{@name.capitalize}"
      @go_name = camelize(name)
      @go_type = full_go_type
      @go_invocation_type = "#{go_type}Invocation"
      @go_request_type = "#{go_type}Request"
      @go_response_type = "#{go_type}Response"
      @input = desc[:input] && InputOutput.new(self, :io, :input, desc[:input])
      @output = desc[:output] && InputOutput.new(self, :io, :output, desc[:output])
      @http_method = desc[:method]
      @path = desc[:path]
      @metadata = desc[:meta] && Metadata.new(self, desc[:meta])
      @blocking = desc[:blocking]
    end

    # Return action name with all aliases, camelized
    # @return [Array<String>]
    def all_names
      yield(go_name)
      aliases.each { |v| yield(camelize(v)) }
    end

    # @return [Boolean]
    def has_path_params?
      path =~ /\{[a-zA-Z0-9\-_]+\}/
    end

    # @return [Boolean]
    def has_input?
      input && input.parameters.any?
    end

    # @return [Boolean]
    def has_output?
      output && output.parameters.any?
    end

    def input_output
      %i[input output].select do |v|
        send(v) && send(v).parameters.any?
      end.map { |v| send(v) }
    end

    def blocking?
      @blocking
    end

    def resolve_associations
      input_output.each(&:resolve_associations)

      metadata && metadata.resolve_associations
    end

    def <=>(other)
      go_name <=> other.go_name
    end

    protected

    attr_reader :prefix

    def full_go_type
      names = []
      names << camelize(prefix) if prefix
      names << 'Action'
      names.concat(resource.resource_path.map(&:go_name))
      names << go_name
      names.join
    end
  end
end
