HaveAPI
=======
HaveAPI defines a protocol for self-describing RESTful APIs. This repository contains
documentation of said protocol and a reference implementation in Ruby, in the form of
a framework for building APIs.

## What is a self-describing API?
A self-describing API responds to HTTP method `OPTIONS` and returns description
of available resources and their actions. The description contains
a full list of parameters, their labels, text notes, data types, validators
and example usage.

Clients use the self-description to learn how to communicate with the API,
which they otherwise know nothing about.

## Motivation
Whenever you create an API server, you need to implement clients in various programming
languages to work with it. Even if you make all APIs similar using e.g. REST or SOAP,
you still need clients to know what resources and actions the API has, what are their
parameters, and so on.

When your API speaks the HaveAPI protocol, you can use pre-created clients that will
know how to work with it. You can do this by using this framework to handle all
HaveAPI-protocol stuff for you, or you can implement the [protocol](doc/protocol.md)
on your own.

At the moment, the following clients are available:

- Ruby client library and CLI: https://github.com/vpsfreecz/haveapi-client
- PHP client: https://github.com/vpsfreecz/haveapi-client-php
- JavaScript client: https://github.com/vpsfreecz/haveapi-client-js

If there isn't a client in the language you need, you can [create it](doc/create-client.md).

Complex applications can be built on top of these basic clients, e.g.:

- [haveapi-webui](https://github.com/vpsfreecz/haveapi-webui), a generic web administration
  for HaveAPI-based APIs
- [haveapi-fs](https://github.com/vpsfreecz/haveapi-fs), a FUSE based filesystem that can
  mount any HaveAPI-based API

## Protocol features
- Creates RESTful APIs usable even with simple HTTP client, should it be needed
- A change in the API is immediately reflected in all clients when they re-download the
  documentation
- Generic interface for clients - one client can be used to access all APIs
  that implement this protocol
- Supports API versioning
- Standardised authentication methods
- Defines action input/output parameters and their validators
- Clients can monitor progress of long-running actions

## Server framework features
- Handles network communication, authentication, authorization, input/output formats
  and parameters, you need only to define resources and actions
- By writing the code you get the documentation for free
- Auto-generated online HTML documentation
- ORM integration
  - ActiveRecord
    - integrated with controller
    - loads and documents validators from models
    - eager loading
  - easy to support other ORM frameworks

## Usage
This text might not be complete or up-to-date, as things still often change.
Full use of HaveAPI may be seen
in [vpsadmin-api](https://github.com/vpsfreecz/vpsadmin-api)
([online doc](https://api.vpsfree.cz)), which may serve as an example of how
are things meant to be used.

All resources and actions are represented by classes. They all must be stored
in a module, whose name is later given to HaveAPI. HaveAPI then searches all
classes in this module and builds your API.

For the purposes of this document, all resources will be in module `MyAPI`.

### Example
This is a basic example, it does not show all options and functions.

Let's assume a model:

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
      output(:object_list) do
        use :id
        use :common
      end

      # Determine if current user can use this action.
      # allow/deny immediately returns from this block.
      # Default rule is deny.
      authorize do |u|
        allow if u.role == 'admin'
        deny  # deny is implicit, so it may be omitted
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

      # Helper method returning a query for all users
      def query
        ::User.all
      end

      # This method is called if the request has meta[:count] = true
      def count
        query.count
      end

      # Execute action, return the list
      def exec
        query.limit(input[:limit]).offset(input[:offset])
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create new user'

      input do
        use :common
      end

      output do
        use :id
        use :common
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

      def exec
        user = ::User.new(input)

        if user.save
          ok(user)
        else
          error('save failed', user.errors.to_hash)
        end
      end
    end
  end
end
```

### What you get
From this piece of code, HaveAPI will generate a self-describing API.
It will contain resource `User` with actions `Index` and `Create`,
using which you can list existing users and create new ones.

You can use any of the available clients to work with the API.

### Run the example
```ruby
api = HaveAPI::Server.new(MyAPI)

# Use HTTP basic auth
class BasicAuth < HaveAPI::Authentication::Basic::Provider
  def find_user(request, username, password)
      User.authenticate(username, password)
  end
end

api.use_version(:all)
api.auth_chain << BasicAuth
api.mount('/')

api.start!
```

This should start the application using WEBrick. Check
[http://localhost:4567](http://localhost:4567).

- `GET /` - a list of API versions
- `GET /doc` - HaveAPI documentation
- `GET /v1/` - documentation for version 1
- `OPTIONS /` - description for the whole API
- `OPTIONS /v1/` - description for API version 1

and more.

### Run with rackup
Use the same code as above, only the last line would be

```ruby
run api.app
```

## Authentication
HaveAPI defines an interface for creating authentication providers.
HTTP basic auth and token providers are built-in.

Authentication options are self-described. A client can choose what authentication
method it understands and wants to use.

## Authorization
HaveAPI provides means for authorizing user access to actions. This process
is not self-described.

If the user is authenticated when requesting self-description, only allowed
resources, actions and parameters will be returned.

## Validation of input data
Because validators are a part of the API's documentation, the clients can
perform client-side validation before the data is sent to the API server.

## Blocking actions
Blocking mode is for actions whose execution is not immediate but takes an unspecified
amount of time. HaveAPI protocol allows clients to monitor progress of such actions
or cancel their execution.

## Read more
 - [Protocol definition](doc/protocol.md)
 - [How to create a client](doc/create-client.md)

## Contributing

1. Fork it ( https://github.com/vpsfreecz/haveapi/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
