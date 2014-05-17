HaveAPI
=======
A framework for creating self-describing APIs.

Note: HaveAPI is under development. It is not stable, the interface may change.

## What is self-describing API?
Self-describing API responds to HTTP method `OPTIONS` and returns description
of available resources, their actions and parameters. The description contains
full list of parameters, their labels, text notes, data types, validators
and example usage.

You can ask for description either whole API, specific version of the API
or concrete action.

The description is encoded in JSON.

## Main features
- RESTful - divided into resources, which may be nested, and their actions
- By writing the code you get documentation for free
- Auto-generated online HTML documentation
- Generic interface for clients - one client can be used to access all APIs
  built using this framework
- A change in the API is immediately reflected in all clients
- Supports API versioning
- Ready for ActiveRecord - validators from models are included in the
  self-description

## Usage
This text might not be complete or up-to-date, as things still often change.
Full use of HaveAPI may be seen
in [vpsadminapi](https://github.com/vpsfreecz/vpsadminapi), which may serve
as an example and how are things meant to be used.

All resources and actions are represented by classes. They all must be stored
in a module, whose name is later given to HaveAPI.

HaveAPI then searches all classes in that module and constructs your API.

For the purposes of this document, all resources will be in module `MyAPI`.

### Example
This is a basic example, it does not show all options and functions.

Assume you have a model:

```ruby
class User < ActiveRecord::Base
  validates :login, :full_name, :role, presence: true
  validates :login, format: {
      with: /[a-zA-Z\.\-]{3,30}/,
      message: 'not a valid login'
  }, uniqueness: true
  validates :role, inclusion: {
    in: %w(admin user),
    message '%{value} is not a valid role'
  }
  
  # An example authentication with plain text password
  def self.authenticate(username, password)
    u = User.find_by(login: username)

    if u
      u if u.password == password
    end
  end
end
```

Resource user might look like this:
```ruby
module MyAPI
  class User < HaveAPI::Resource
    # This resource belongs to version 1.
    # It is also possible to put resource to multiple versions, e.g. [1, 2]
    version 1
    
    # Provide description for this resource
    desc 'Manage users'
    
    # ActiveRecord model to load validators from
    model ::User
    
    # Require authentication, this is the default
    auth true
    
    # Create a named group of shared params, that may be later included
    # by actions.
    params(:id) do
      id :id, label: 'User ID'
    end
    
    params(:common) do
      string :login, label: 'Login', desc: 'Used for authentication'
      string :full_name, label: 'Full name'
      string :role, label: 'User role', desc: 'admin or user'
    end
    
    # Actions
    # Module HaveAPI::Actions::Default contains helper classes that define
    # HTTP methods and routes for generic actions.
    class Index < HaveAPI::Actions::Default::Index
      desc 'List all users'
      
      # There are no input parameters
      
      # Output parameters
      # :users means, that the list of users will be in hash with key :users
      output(:users) do
        use :id
        use :common
      end
      
      # Determine if current user can use this action.
      # allow/deny immediately returns from this block.
      # Default rule is deny.
      authorize do |u|
        allow if u.role == 'admin'
        deny
      end
      
      # Provide example usage
      example do
        request({})
        response({
          users: [
            {
              id: 1,
              login: 'myuser',
              full_name: 'My Very Name'
            }
          ]
        })
        comment 'Get a list of all users like this'
      end
      
      # Execute action, return the list
      def exec
        ret = []
        
        ::User.all.each do |u|
          ret << u.attributes
        end
        
        ret
      end
    end
    
    class Create < HaveAPI::Actions::Default::Create
      desc 'Create new user'
      
      input do
        use :common
      end
      
      output do
        use :id
      end
      
      authorize do |u|
        allow if u.role == 'admin'
        deny
      end
      
      example do
        request({
          user: {
            login: 'anotherlogin',
            full_name: 'My Very New Name'
          }
        })
        response({
          user: {
            id: 2
          }
        })
        comment 'Create new user like this'
      end
    end
  end
end
```

### What you get
From this piece of code, HaveAPI will generate self-describing API.
It will contain resource `User` with actions `Index` and `Create`.

HaveAPI will also load validators from the model and it will be included
in the self-description.

Online HTML documentation will also be available.

### Run example
```ruby
api = HaveAPI::Server.new(MyAPI)

# Define authentication method, the block should return current user object.
api.authenticate do |request|
  user = nil
  
  auth = Rack::Auth::Basic::Request.new(request.env)
  if auth.provided? && auth.basic? && auth.credentials
    user = User.authenticate(*auth.credentials)
  end

  user
end

api.use_version(:all)
api.set_default_version(1)
api.mount('/')

api.start!
```

This should start the application using WEBrick. Check
[http://localhost:4567](http://localhost:4567).

- `GET /` - a list of API versions
- `GET /v1/` - documentation for version 1
- `OPTIONS /` - description for whole API
- `OPTIONS /v1/` - description for API version 1

### Run with rackup
Use the same code as above, only the last line would be

```ruby
run api.app
```

## Envelope
In addition to output parameters specified for all actions, every API response
(except description) is wrapped in an envelope. The envelope reports if action
succeeded or failed, provides return value or error messages.

    {
      "status": true if action succeeded or false if error occured,
      "response": return value,
      "message": error message, if status is false,
      "errors: {
        "parameter1": ["list", "of", "errors"],
        "parameter2": ["and", "so", "on"]
      }
    }

## Authentication
HaveAPI does not deal with authentication itself. This process is delegated to
the application, which can use HTTP basic auth or any other method.

## Authorization
HaveAPI provides means for authorizing user access to actions. This process
is not self-described.

If the user is authenticated when requesting self-description, only allowed
resources, actions and parameters will be returned.

## Input/output formats
For now, the only supported input/output format is JSON.

## Contributing

1. Fork it ( https://github.com/vpsfreecz/haveapi/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
