require 'haveapi/go_client/parameters/base'

module HaveAPI::GoClient
  class Parameters::CustomInput < Parameters::Base
    handle do |role, direction, _name, desc|
      role == :io && direction == :input && desc[:type] == 'Custom'
    end

    def initialize(io, name, desc)
      super
      @nullable = desc[:nullable] == true
    end

    def nillable?
      @nullable
    end

    protected

    def do_resolve
      if io.action.http_method == 'GET'
        raise "unsupported Custom query input '#{name}' for action '#{io.action.full_dot_name}'"
      end

      @go_in_type = 'json.RawMessage'
    end
  end
end
