# Client definition
It is necessary to differentiate between clients for HaveAPI based APIs
and clients to work with your API instance. This document describes
the former. If you only want to use your API, you should check a list
of available clients and pick the one in the right language. Only when
there isn't a client already available in the language you want, then
continue reading.

# Design rules
The client must completely depend on the API description:

 - it has no assumptions and API-specific code,
 - it does not know any resources, actions and parameters,
 - everything the client knows must be found out from the API description.

All clients should use a similar paradigm, so that it is possible to use
clients in different languages in the same way, as far as the language syntax
allows. Clients bundled with HaveAPI may serve as a model. A client should
use all the advantages and coding styles of the language it is written
in (e.g. use objects in object oriented languages).

A model paradigm (in no particular language):

    // Create client instance
    api = new HaveAPI.Client("https://your.api.tld")

    // Authenticate
    api.authenticate("basic", {"user": "yourname", "password": "yourpassword"})

    // Access resources and actions
    api.<resource>.<action>( { <parameters> } )
    api.user.new({"name": "Very Name", "password": "donottellanyone"})
    api.user.list()
    api.nested.resource.deep.list()

    // Pass IDs to resources
    api.nested(1).resource(2).deep.list()

    // Object-like access
    user = api.user.show(1)
    user.id
    user.name
    user.destroy()

    // Logout
    api.logout()

# Necessary features to implement
A client should implement all of the listed features in order to be useful.

## Resource tree
The client gives access to all listed resources and their actions.

In scripting languages, resources and actions are usually defined as dynamic
properties/objects/methods, depending on the language.

## Input/output parameters
Allow sending input parameters and accessing the response.

## Input/output formats
A client must send appropriate HTTP header `Accept`. As only JSON is by now built-in
in HaveAPI, it should send `application/json`.

## Authentication
All authentication methods that are built-in the HaveAPI should be supported
if possible. The client should choose suitable authentication method
for its purpose and allow the developer to select the authentication method
if it makes sense to do so.

It is a good practise to implement authentication methods as plugins,
so that developers may add custom authentication providers easily.

## Object-like access
A client must interpret the API response according to action output layout.
Layouts `object` and `object_list` should be handled as object instances,
if the language allows it.

Object instances represent the object fetched from the database. Received
parameters are accessed via object attributes/properties. Actions are defined
as instance methods. Objects may have associations to other resources which
must be made available and be easy to access.

# Supplemental features
Following features are supplemental. It is good to support them,
but is not necessary.

## Client-side validations
Client may make use of described validators and validate the input before
sending it to the API, to lessen the API load and make it more user-friendly.

However, as the input is validated on the server anyway, it does not have
to be implemented.

Typed parameter validation is separate from validator-based validation and is always
recommended. A client should enforce the type rules from
[Typed input validation](typed-input-validation.md) before sending requests. Even in
strongly typed languages, runtime checks are needed for values like NaN/Inf and for
datetime string formatting.

## Metadata channel
Metadata channel is currently used to specify what associated resources should
be prefetched and whether an object list should contain total number of items.

Metadata is nothing more than a hash in input parameters under key `_meta`.

## Blocking actions
Useful for APIs with long-running actions. Clients can check state of such actions
using resource `ActionState`. Because this resource is automatically present in all
APIs that use blocking actions, client libraries expose this resource to the developer
just as any other resource in the API.

However, you may wish to integrate it in your client and provide ways for the action
call to block/accept callbacks.
