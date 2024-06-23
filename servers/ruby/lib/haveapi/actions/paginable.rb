module HaveAPI::Actions
  module Paginable
    def self.included(action)
      action.input do
        integer :offset, label: 'Offset', desc: 'The offset of the first object',
                         number: { min: 0 }
        integer :limit, label: 'Limit', desc: 'The number of objects to retrieve',
                        number: { min: 0 }
      end
    end
  end
end
