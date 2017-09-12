module HaveAPI
  module Actions
    module Default
      class Index < Action
        route ''
        http_method :get
        aliases %i(list)

        meta(:global) do
          input do
            bool :count, label: 'Return the count of all items', default: false
          end

          output do
            integer :total_count, label: 'Total count of all items'
          end
        end

        include HaveAPI::Actions::Paginable

        def pre_exec
          set_meta(total_count: count) if meta[:count]
        end

        # Return the total count of items.
        def count

        end
      end

      class Create < Action
        route ''
        http_method :post
        aliases %i(new)
      end

      class Show < Action
        route ->(r){ r.singular ? '' : ':%{resource}_id' }
        http_method :get
        aliases %i(find)
      end

      class Update < Action
        route ->(r){ r.singular ? '' : ':%{resource}_id' }
        http_method :put
      end

      class Delete < Action
        route ->(r){ r.singular ? '' : ':%{resource}_id' }
        http_method :delete
        aliases %i(destroy)
      end
    end
  end
end
