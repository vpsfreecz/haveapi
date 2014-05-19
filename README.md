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
        -a, --api URL                    API URL
            --list-versions              List all available API versions
            --list-resources VERSION     List all resource in API version
            --list-actions VERSION       List all resources and actions in API version
        -r, --raw                        Print raw response as is
        -u, --username USER              User name
        -p, --password PASSWORD          Password
        -v, --[no-]verbose               Run verbosely
        -h, --help                       Show this message
  
Using the API example from
[HaveAPI README](https://github.com/vpsfreecz/haveapi/blob/master/README.md#example),
users would be listed with:

    $ haveapi-cli -a https://your.api.tld user index -u yourname -p yourpassword
    
Nested resources and object IDs:

    $ haveapi-cli -a https://your.api.tld user.invoice index 10 -u yourname -p yourpassword

where `10` is user ID.
 
### Client library
```ruby
require 'haveapi/client'

api = HaveAPI::Client::Client.new('https://your.api.tld')
api.login('yourname', 'yourpassword')

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
