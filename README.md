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

## CLI
    $ haveapi-cli -h
    Usage: haveapi-cli [options] <resource> <action> [objects ids] [-- [parameters]]
        -u, --api URL                    API URL
        -a, --auth METHOD                Authentication method
            --list-versions              List all available API versions
            --list-auth-methods [VERSION]
                                         List available authentication methods
            --list-resources [VERSION]   List all resource in API version
            --list-actions [VERSION]     List all resources and actions in API version
            --version VERSION            Use specified API version
        -c, --columns                    Print output in columns
        -H, --no-header                  Hide header row
        -L, --list-parameters            List output parameters
        -o, --output PARAMETERS          Parameters to display, separated by a comma
        -r, --rows                       Print output in rows
        -s, --sort PARAMETER             Sort output by parameter
            --save                       Save credentials to config file for later use
            --raw                        Print raw response as is
            --timestamp                  Display Datetime parameters as timestamp
            --utc                        Display Datetime parameters in UTC
            --localtime                  Display Datetime parameters in local timezone
            --date-format FORMAT         Display Datetime in custom format
            --[no-]block                 Toggle action blocking mode
            --timeout SEC                Fail when the action does not finish within the timeout
        -v, --[no-]verbose               Run verbosely
            --client-version             Show client version
            --protocol-version           Show protocol version
            --check-compatibility        Check compatibility with API server
        -h, --help                       Show this message
  
Using the API example from
[HaveAPI README](https://github.com/vpsfreecz/haveapi#example),
users would be listed with:

    $ haveapi-cli --url https://your.api.tld --auth basic --username yourname --password yourpassword user list
    
Nested resources and object IDs:

    $ haveapi-cli --url https://your.api.tld --auth basic --username yourname --password yourpassword user.invoice list 10

where `10` is user ID.

User credentials can be saved to a config:

    $ haveapi-cli --url https://your.api.tld --auth basic --username yourname --password yourpassword --save user list
    
When saved, they don't have to be specified as command line options:

    $ haveapi-cli --url https://your.api.tld user list
 
List options specific to authentication methods:

    $ haveapi-cli --url https://your.api.tld --auth basic -h
    $ haveapi-cli --url https://your.api.tld --auth token -h
 
List action parameters with examples:

    $ haveapi-cli --url https://your.api.tld user new -h

Provide action parameters (notice the ``--`` separator):

    $ haveapi-cli --url https://your.api.tld user new -- --login mylogin --full-name "My Full Name" --role user

 
## Client library
```ruby
require 'haveapi/client'

api = HaveAPI::Client::Client.new('https://your.api.tld')
api.authenticate(:basic, user: 'yourname', password: 'yourpassword')

api.user.list.each do |user|
    puts user.login
end

user = api.user.find(10)
p user.invoice
user.destroy

p api.user.create({
  login: 'mylogin',
  full_name: 'Very Full Name',
  role: 'user'
})

user = api.user.new
user.login = 'mylogin'
user.full_name = 'Very Full Name'
user.role = 'user'
user.save
p user.id
```
