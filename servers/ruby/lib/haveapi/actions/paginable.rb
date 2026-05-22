module HaveAPI::Actions
  module Paginable
    MAX_LIMIT = 1_000

    def self.included(action)
      action.input do
        integer :from_id, label: 'From ID', desc: 'List objects with greater/lesser ID',
                          number: { min: 0 }
        integer :limit, label: 'Limit', desc: 'Number of objects to retrieve',
                        number: { min: 0, max: MAX_LIMIT }
      end
    end
  end
end
