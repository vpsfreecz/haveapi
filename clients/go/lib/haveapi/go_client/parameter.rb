require 'haveapi/go_client/utils'

module HaveAPI::GoClient
  class Parameter
    include Utils

    # @return [InputOutput]
    attr_reader :io

    # Parameter name in the API
    # @return [String]
    attr_reader :name

    # HaveAPI data type
    # @return [String]
    attr_reader :type

    # Parameter name in Go
    # @return [String]
    attr_reader :go_name

    # Go type for action input
    # @return [String]
    attr_reader :go_in_type

    # Go type for action output
    # @return [String]
    attr_reader :go_out_type

    # Pointer to associated resource
    # @return [Association, nil]
    attr_reader :association

    def initialize(io, name, desc)
      @io = io
      @name = name
      @type = desc[:type]
      @desc = desc
      @go_name = camelize(name)
    end

    def resolve
      @association = Association.new(self, desc) if type == 'Resource'
      @go_in_type = get_go_type(desc[:type], false)
      @go_out_type = get_go_type(desc[:type], true)
      @desc = nil
    end

    protected
    attr_reader :desc

    def get_go_type(v, assoc)
      case v
      when 'String', 'Text', 'Datetime'
        'string'
      when 'Integer'
        'int64'
      when 'Float'
        'float64'
      when 'Boolean'
        'bool'
      when 'Resource'
        assoc ? association.go_type : 'int64'
      else
        fail "unsupported data type '#{v}'"
      end
    end
  end
end
