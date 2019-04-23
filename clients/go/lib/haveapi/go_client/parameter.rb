require 'haveapi/go_client/utils'

module HaveAPI::GoClient
  class Parameter
    include Utils

    attr_reader :io, :name, :type, :go_name, :go_in_type, :go_out_type, :association

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
