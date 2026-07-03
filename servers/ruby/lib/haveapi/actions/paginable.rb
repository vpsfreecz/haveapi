module HaveAPI::Actions
  module Paginable
    MAX_LIMIT = 1_000

    def self.included(action)
      action.input do
        integer :from_id,
                label: HaveAPI.message('haveapi.parameters.paginable.from_id.label'),
                desc: HaveAPI.message('haveapi.parameters.paginable.from_id.description'),
                number: { min: 0 }
        integer :limit,
                label: HaveAPI.message('haveapi.parameters.paginable.limit.label'),
                desc: HaveAPI.message('haveapi.parameters.paginable.limit.description'),
                number: { min: 0, max: MAX_LIMIT }
      end
    end
  end
end
