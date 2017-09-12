Empty Project with ActiveRecord
===============================

## Contents
- `config/database.yml` - database configuration
- `db/`
  - `migrate/` - database migrations
  - `schema.rb` - schema dumped by ActiveRecord
- `lib/`
  - `resources/` - contains API resources and actions, it's up to you how you
    structure it, I usually use one file for one resource
    - `dummy.rb` - an example resource
  - `api.rb` - method `API::default` to setup the API
- `models/` - ActiveRecord models, same as in Rails
- `spec/`
  - `spec_helper.rb` - configure rspec and add helper methods
  - `dummy_spec.rb` - example tests for the `Dummy` resource
- `config.ru` - used to run the API server
- `Gemfile` - necessary dependencies
- `Rakefile` - contains tasks for testing with rspec and ActiveRecord

## How to run it
Enter the project directory, install dependencies using `bundle install` and
run with `rackup`.

## Usage
`rackup` will start a HTTP server that will serve the API. It will tell you
on which port it's listening. In my case, the server listens on
`http://localhost:9292`:

- `GET http://localhost:9292` - list of API versions, links to documentation
- `GET http://localhost:9292/v1.0/` - documentation for API version `1.0`
- `OPTIONS http://localhost:9292` - JSON-formatted description of the whole API
- `OPTIONS http://localhost:9292/v1.0/` - JSON-formatted description of API version `1.0`

You can use any client that implements the
[HaveAPI protocol](https://github.com/vpsfreecz/haveapi).

In addition to the basic project template, this one has several rake tasks from
ActiveRecord, e.g.:

    $ rake -T
    rake db:create_migration
    rake db:migrate
    rake db:migrate:status
    rake db:rollback
    rake db:schema:dump

## Testing
Included is support for testing with `rspec`. Notice how the `spec/spec_helper.rb`
adds helper methods that you can use in your tests.
