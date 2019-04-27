require 'haveapi/go_client/parameters/base'

module HaveAPI::GoClient
  class Parameters::Resource < Parameters::Base
    handle do |role, direction, name, desc|
      desc[:type] == 'Resource'
    end

    # Pointer to the associated resource
    # @return [Parameters::Association]
    attr_reader :association

    protected
    def do_resolve
      @association = Parameters::Association.new(self, desc)
      @go_in_type = 'int64'
      @go_out_type = association.go_type
    end
  end
end
