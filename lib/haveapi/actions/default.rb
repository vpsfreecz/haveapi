module HaveAPI
  module Actions
    module Default
      class Index < Action
        route ''
        http_method :get
        aliases %i(list)

        include HaveAPI::Actions::Paginable
      end

      class Create < Action
        route ''
        http_method :post
        aliases %i(new)
      end

      class Show < Action
        route ':%{resource}_id'
        http_method :get
        aliases %i(find)
      end

      class Update < Action
        route ':%{resource}_id'
        http_method :put
      end

      class Delete < Action
        route ':%{resource}_id'
        http_method :delete
        aliases %i(destroy)
      end
    end
  end
end
