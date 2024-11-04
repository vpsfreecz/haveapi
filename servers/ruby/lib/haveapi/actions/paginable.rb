module HaveAPI::Actions
  module Paginable
    def self.included(action)
      action.input do
        integer :from_id, label: 'From ID', desc: 'List objects with greater ID',
                          number: { min: 0 }
        integer :limit, label: 'Limit', desc: 'Number of objects to retrieve',
                        number: { min: 0 }
      end
    end
  end
end
