module API::Resources
  class Dummy < HaveAPI::Resource
    desc 'Dummy resource'
    # version '1.0'
    
    # Associate this resource with ActiveRecord model.
    # This will let us return AR models and HaveAPI will know how to work
    # with them, i.e. extract parameters. HaveAPI will also fetch validators
    # from the model and add them to appropriate input parameters.
    model ::Dummy

    # Create a named groups of parameters
    params(:common) do
      string :name
    end
    
    params(:all) do
      id :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List dummies'
      auth false

      # Specify action's output
      output(:object_list) do
        # Include a named group of parameters
        use :all
      end

      # Allow access to everyone
      authorize { allow }
      
      # Return a prepared query object
      def query
        ::Dummy.all
      end

      # Called when meta[count] is true, i.e. the client has requested the total
      # count of objects
      def count
        query.count
      end

      def exec
        # If the `Dummy` model had associations, `with_includes` would fetch them
        # all at once, this can tremendously speed up loading of many objects.
        with_includes(query)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show a dummy'
      auth false

      # Specify action's output
      output do
        # Include a named group of parameters
        use :all
      end

      # Allow access to everyone
      authorize { allow }
      
      def exec
        ::Dummy.find(params[:dummy_id])

      rescue ActiveRecord::RecordNotFound => e
        error("dummy with id '#{params[:dummy_id]}' not found")
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a dummy'
      auth false
      
      input do
        use :common

        # Ensure that name is always set
        patch :name, required: true
      end

      output do
        use :all
      end

      authorize { allow }

      def exec
        ::Dummy.create!(input)

      rescue ActiveRecord::RecordInvalid => e
        errors('create failed', e.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete a dummy'
      auth false

      authorize { allow }

      def exec
        ::Dummy.find(params[:dummy_id]).destroy!

        # This action returns no parameters, just indicate success
        ok

      rescue ActiveRecord::RecordNotFound
        error("dummy with id '#{params[:dummy_id]}' not found")
      end
    end
  end
end
