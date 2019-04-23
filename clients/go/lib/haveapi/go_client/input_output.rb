require 'haveapi/go_client/utils'

module HaveAPI::GoClient
  class InputOutput
    include Utils

    attr_reader :action, :direction, :layout, :namespace, :parameters, :go_type,
      :go_namespace

    def initialize(action, direction, desc)
      @action = action
      @direction = direction
      @layout = desc[:layout]
      @namespace = desc[:namespace]
      @parameters = desc[:parameters].map do |k, v|
        Parameter.new(self, k, v)
      end.reject { |p| p.type == 'Custom' }
      @go_type = action.go_type + direction.to_s.capitalize
      @go_namespace = camelize(desc[:namespace])
    end

    def resolve_associations
      parameters.each { |p| p.resolve }
    end
  end
end
