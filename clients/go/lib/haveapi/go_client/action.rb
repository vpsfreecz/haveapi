require 'haveapi/go_client/utils'

module HaveAPI::GoClient
  class Action
    include Utils

    attr_reader :resource, :name, :aliases, :go_name, :go_type, :input, :output,
      :http_method, :url, :go_invocation_type, :go_request_type, :go_response_type

    def initialize(resource, name, desc)
      @resource = resource
      @name = name.to_s
      @aliases = desc[:aliases]
      @go_name = camelize(name)
      @go_type = full_go_type
      @go_invocation_type = go_type + 'Invocation'
      @go_request_type = go_type + 'Request'
      @go_response_type = go_type + 'Response'
      @input = desc[:input] && InputOutput.new(self, :input, desc[:input])
      @output = desc[:output] && InputOutput.new(self, :output, desc[:output])
      @http_method = desc[:method]
      @url = desc[:url]
    end

    def all_names
      yield(go_name)
      aliases.each { |v| yield(camelize(v)) }
    end

    def has_url_params?
      url =~ /:[a-zA-Z\-_]+/
    end

    def has_input?
      input && input.parameters.any?
    end

    def has_output?
      output && output.parameters.any?
    end

    def input_output
      %i(input output).select do |v|
        send(v) && send(v).parameters.any?
      end.map { |v| send(v) }
    end

    def resolve_associations
      input_output.each do |io|
        io.resolve_associations
      end
    end

    protected
    def full_go_type
      names = ['Action']
      names.concat(resource.resource_path.map(&:go_name))
      names << go_name
      names.join('')
    end
  end
end
