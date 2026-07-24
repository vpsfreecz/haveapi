require 'haveapi/go_client/parameters/base'

module HaveAPI::GoClient
  class Parameters::Custom < Parameters::Base
    handle do |role, direction, name, desc|
      desc[:type] == 'Custom' \
        && !(role == :global_meta && direction == :input && name == 'includes')
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
      @go_in_type = @go_out_type = 'interface{}'
    end
  end
end
