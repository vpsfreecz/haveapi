module API::Resources
  class User < HaveAPI::Resource
    desc 'Manage users'
    
    # Associate this resource with ActiveRecord model.
    # This will let us return AR models and HaveAPI will know how to work
    # with them, i.e. extract parameters. HaveAPI will also fetch validators
    # from the model and add them to appropriate input parameters.
    model ::User

    # Create a named groups of parameters
    params(:common) do
      string :username
      bool :is_admin
    end
    
    params(:all) do
      id :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List users'

      # Specify action's output
      output(:object_list) do
        # Include a named group of parameters
        use :all
      end

      # Allow access to everyone
      authorize { allow }
      
      # Return a prepared query object
      def query
        ::User.all
      end

      # Called when meta[count] is true, i.e. the client has requested the total
      # count of objects
      def count
        query.count
      end

      def exec
        # If the `User` model had associations, `with_includes` would fetch them
        # all at once, this can tremendously speed up loading of many objects.
        with_includes(query)
      end
    end

    class Current < HaveAPI::Action
      desc 'Get the currently logged user'

      output do
        use :all
      end

      authorize { allow }

      def exec
        current_user
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show a user'

      # Specify action's output
      output do
        # Include a named group of parameters
        use :all
      end

      # Allow access to everyone
      authorize { allow }
      
      def exec
        ::User.find(params[:user_id])

      rescue ActiveRecord::RecordNotFound => e
        error("user with id '#{params[:user_id]}' not found")
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a user'
      
      input do
        use :common

        # Ensure that username is always set
        patch :username, required: true

        string :password, required: true, length: {min: 5}
      end

      output do
        use :all
      end

      # Only admins can create new users
      authorize { |user| allow if user.is_admin }

      def exec
        ::User.create!(
          username: input[:username],
          password: ::User.hash_password(input[:password]),
        )

      rescue ActiveRecord::RecordInvalid => e
        errors('create failed', e.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete a user'

      authorize { |user| allow if user.is_admin }

      def exec
        ::User.find(params[:user_id]).destroy!

        # This action returns no parameters, just indicate success
        ok

      rescue ActiveRecord::RecordNotFound
        error("user with id '#{params[:user_id]}' not found")
      end
    end
  end
end
