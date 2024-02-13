require 'haveapi/go_client/utils'

module HaveAPI::GoClient
  class Parameters::Association
    include Utils

    # @return [Parameter]
    attr_reader :parameter

    # @return [String]
    attr_reader :go_type

    # @return [String]
    attr_reader :go_value_id

    # @return [String]
    attr_reader :go_value_label

    # @return [Resource]
    attr_reader :resource

    def initialize(param, desc)
      @parameter = param
      @resource = find_resource(desc[:resource])
      @go_type = resource.actions.detect { |a| a.name == 'show' }.output.go_type
      @go_value_id = camelize(desc[:value_id])
      @go_value_label = camelize(desc[:value_label])
    end

    protected

    def find_resource(path)
      root = parameter.io.action.resource.api_version
      path = path.clone

      loop do
        name = path.shift
        resource = root.resources.detect { |r| r.name == name }

        if resource.nil?
          raise "associated resource '#{name}' not found in " +
                (root.is_a?(ApiVersion) ? 'root' : root.resource_path.map(&:name).join('.'))

        elsif path.empty?
          return resource

        else
          root = resource
        end
      end

      raise 'programming error'
    end
  end
end
