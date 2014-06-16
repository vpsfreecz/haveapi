HaveAPI-Client
--------------
HaveAPI-Client is a Ruby CLI and client library for APIs built with
[HaveAPI framework](https://github.com/vpsfreecz/haveapi).

## Installation

Add this line to your application's Gemfile:

    gem 'haveapi-client'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install haveapi-client

## Usage
### CLI
    $ haveapi-cli -h
    Usage: haveapi-cli [options] <resource> <action> [objects ids] [-- [parameters]]
        -u, --api URL                    API URL
        -a, --auth METHOD                Authentication method
            --list-versions              List all available API versions
            --list-auth-methods [VERSION]
                                         List available authentication methods
            --list-resources [VERSION]   List all resource in API version
            --list-actions [VERSION]     List all resources and actions in API version
        -r, --raw                        Print raw response as is
        -s, --save                       Save credentials to config file for later use
        -v, --[no-]verbose               Run verbosely
        -h, --help                       Show this message
  
Using the API example from
[HaveAPI README](https://github.com/vpsfreecz/haveapi/blob/master/README.md#example),
users would be listed with:

    $ haveapi-cli --url https://your.api.tld --auth basic --username yourname --password yourpassword user index
    
Nested resources and object IDs:

    $ haveapi-cli --url https://your.api.tld --auth basic --username yourname --password yourpassword user.invoice index 10

where `10` is user ID.

User credentials can be saved to a config:

    $ haveapi-cli --url https://your.api.tld --auth basic --username yourname --password yourpassword --save user index
    
When saved, they don't have to be specified as command line options:

    $ haveapi-cli --url https://your.api.tld user index
 
### Client library
```ruby
require 'haveapi/client'

api = HaveAPI::Client::Client.new('https://your.api.tld')
api.authenticate(:basic, user: 'yourname', password: 'yourpassword')

response = api.user.index
p response.ok?
p response.response

p api.user(10).invoice
p api.user(10).delete
p api.user(10).delete!
p api.user.delete(10)

p api.user.create({
  login: 'mylogin',
  full_name: 'Very Full Name',
  role: 'user'
})
```
