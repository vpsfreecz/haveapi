module HaveAPI::Actions
  module Paginable
    def self.included(action)
      action.input do
        integer :offset, label: 'Offset', desc: 'The offset of the first object'
        integer :limit, label: 'Limit', desc: 'The number of objects to retrieve'
      end
    end
  end
end
