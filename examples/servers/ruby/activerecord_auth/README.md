Empty Project with ActiveRecord
===============================

## Important Files
- `db/migrate/0001_setup_database.rb` - create tables for users and auth tokens
- `lib/`
  - `authentication/{basic,token}.rb` - authentication backends
  - `resources/user.rb` - User resource
  - `api.rb` - configure authentication chain
- `models/{user,auth_token}.rb` - models
- `Rakefile` - task to create admin users

## Usage
This API includes support for two authentication methods: `basic` and `token`.
There is a model for storing users and a model for authentication tokens, see
the database migration in `db/migrate/0001_setup_database.rb`.

In this case, the first user has to be created using the rake task `create_admin`,
e.g.:

    $ rake create_admin
    Username: admin
    Password: 1234

Password are hashed using the bcrypt algorithm, as can be seen in
`models/user.rb`.

You can then authenticate to this API using the HTTP basic or token authentication
methods. For example:

    # Start the API server, running at http://localhost:9292
    $ rackup

    # Use the CLI from haveapi-client
    $ haveapi-cli -u http://localhost:9292 --auth basic user list
    Username: admin
    Password: 1234

     Id  Username   Is_admin 
      1  admin      true

For the authentication methods to work, the API needs to implement interfaces
from HaveAPI. These can be seen in `lib/api/authentication`. These classes are
then added to HaveAPI's authentication chain in `lib/api.rb`.
