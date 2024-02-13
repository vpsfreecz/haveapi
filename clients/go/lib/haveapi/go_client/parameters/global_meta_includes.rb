require 'haveapi/go_client/parameters/base'

module HaveAPI::GoClient
  class Parameters::GlobalMetaIncludes < Parameters::Base
    handle do |role, direction, name, desc|
      role == :global_meta \
        && direction == :input \
        && name == 'includes' \
        && desc[:type] == 'Custom'
    end

    protected

    def do_resolve
      @go_in_type = @go_out_type = 'string'
    end
  end
end
