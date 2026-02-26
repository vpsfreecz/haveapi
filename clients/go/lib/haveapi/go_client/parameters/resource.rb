require 'haveapi/go_client/parameters/base'

module HaveAPI::GoClient
  class Parameters::Resource < Parameters::Base
    handle do |_role, _direction, _name, desc|
      desc[:type] == 'Resource'
    end

    # Pointer to the associated resource
    # @return [Parameters::Association]
    attr_reader :association

    def initialize(io, name, desc)
      super
      @nullable = desc[:nullable] == true
    end

    def nillable?
      @nullable == true
    end

    protected

    def do_resolve
      @association = Parameters::Association.new(self, desc)
      @go_in_type = 'int64'
      @go_out_type = association.go_type
    end
  end
end
