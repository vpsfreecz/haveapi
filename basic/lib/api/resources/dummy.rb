module API::Resources
  class Dummy < HaveAPI::Resource
    desc 'Dummy resource'
    # version '1.0'
    
    # Some data this resource will serve
    DUMMIES = ['First', 'Second', 'Third']

    # Create a named group of parameters
    params(:all) do
      id :id
      string :name
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List dummies'
      auth false

      # Specify action's output
      output(:hash_list) do
        # Include a named group of parameters
        use :all
      end

      # Allow access to everyone
      authorize { allow }
      
      def exec
        ret = []

        DUMMIES.each_with_index do |v, i|
          ret << {id: i, name: v}
        end

        ret
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show a dummy'
      auth false
      
      # Specify action's output
      output(:hash) do
        # Include a named group of parameters
        use :all
      end

      # Allow access to everyone
      authorize { allow }
      
      def exec
        id = params[:dummy_id] && params[:dummy_id].to_i

        if DUMMIES[id].nil?
          error("Dummy with id '#{id}' not found")
        end

        {id: id, name: DUMMIES[id]}
      end
    end
  end
end
