require 'haveapi/go_client/parameters/base'

module HaveAPI::GoClient
  class Parameters::Typed < Parameters::Base
    handle do |_role, _direction, _name, desc|
      !%w[Custom Resource].include?(desc[:type])
    end

    def initialize(io, name, desc)
      super
      @nullable = desc[:nullable] == true
    end

    def nillable?
      @nullable == true
    end

    protected

    def do_resolve
      @go_in_type = get_go_type(desc[:type])
      @go_out_type = get_go_type(desc[:type])
    end

    def get_go_type(v)
      case v
      when 'String', 'Text', 'Datetime'
        'string'
      when 'Integer'
        'int64'
      when 'Float'
        'float64'
      when 'Boolean'
        'bool'
      else
        raise "unsupported data type '#{v}'"
      end
    end
  end
end
