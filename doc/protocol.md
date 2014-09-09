HaveAPI
=======

[HaveAPI](https://github.com/vpsfreecz/haveapi) is a framework for creating
custom self-describing APIs.

The resulting API aims to be RESTful. It is divided into resources, which may be nested,
and their actions (list, create, update, ...).

Every action has assigned URL, which may be identical for several actions, but
differ in HTTP method.

## Self-description
The API is self-describing. It documents itself. Clients use the self-description
to work with the API. The Self-description contains access URLs, HTTP methods,
input and output parameters and their validators.
A part of description is also an example usage and text notes.

The API responds to ``OPTIONS /``, which returns description of whole
API, containing all its versions. To get description only of selected version,
use e.g. ``OPTIONS /v1/``.

Every action also responds to HTTP method ``OPTIONS``,
with which you can get description for selected action. To distinguish actions with
the same URL, use parameter ``?method=HTTP_METHOD``.

Thanks to this ability, API changes immediately reflects in all clients without
changing a single line of code. A client can also be used on all APIs with compatible
self-describing format, without any changes at all.

## Envelope
In addition to output format specified below, every API response
is wrapped in an envelope.
The envelope reports if action succeeded or failed, provides return value or error
messages.

      {
          "status": true if action succeeded or false if error occured,
          "response": return value,
          "message": error message, if status is false,
          "errors: {
              "parameter1": ["list", "of", "errors"],
              "parameter2": ["and", "so", "on"]
          }
      }

## Description format
In this document, the self-description is encoded in JSON. However, it can
be encoded in any of the supported output formats.

### Version
Version is described as:

    {
        "authentication": {
            ... authentication methods ...
        },
        "resources": {
            ... resources ...
        },
        "help": "/<version>/"
    }

See appropriate section for detailed description of each section.

### Authentication
HaveAPI defines an interface for implementing custom authentication methods.
HTTP basic and token authentication is built-in.

Authentication methods can be set per API version. They are a part of
the self-description, but must be understood by the client.
The client can choose whichever available authentication method he prefers.

#### HTTP basic authentication
HTTP basic authentication needs no other configuration, only informs about its presence.

    "basic": {}

#### Token authentication
Token authentication contains a resource ``token``, that is used
to acquire and revoke token.

Token is acquired by action ``request``. The client provides login and password and gets a token
that is used afterwards. Token has a validity period, which may also be infinity.

Token can be revoked by calling the ``revoke`` action.

    "token": {
        "http_header": "<name of HTTP header to transfer token in, by default X-HaveAPI-Auth-Token>",
        "query_parameter": "<name of query parameter for token, by default auth_token>",
        "resources": {
            "actions": {
                "request": {
                    ...
                    "input": {
                        ...
                        "parameters": {
                            "login": ...
                            "password": ...
                            "validity": ...
                        },
                        ...
                    },
                    "output": {
                        ...
                        "parameters": {
                            "token": ...
                            "valid_to": ...
                        },
                        ...
                    },
                    ...
                 }
                "revoke": ...
            }
        }
    }

The format for ``resources`` section is the same as for any other resource.

### Resources
Each resource is described as:

    "<resource_name>": {
        "description": "Some description that explains everything",
        "actions": {
            ... actions ...
        },
        "resources": {
            ... nested resources ...
        }
    }

### Actions
Every action is described as:

    "<action_name>": {
        "auth": true|false,
        "description": "Describe what this action does",
        "aliases": ["list", "of", "aliases"],
        "input":  {
            "layout": "layout type",
            "namespace": "namespace name",
            "parameters": {
                ... parameters ...
            }
        },
        "output": {
             "layout": "layout type",
             "namespace": "namespace name",
             "parameters": {
                  ... parameters ...
              }
        },
        "examples": [
            ... list of examples ...
        ],
        "url": "URL for this action",
        "method": "HTTP method to be used",
        "help": "URL to get this very description of the action"
    }

#### Layouts
Layout type is specified for input/output parameters. Thanks to the layout type,
clients know how to send the request and how to interpret the response.

Defined layout types:

 - object - mainly the response is to be treated as an instance of a resource
 - object_list - list of objects
 - hash - simply a hash of parameters, it is to be treated as such
 - hash_list - list of hashes

In client libraries, the ``object`` layout output usually results in returning
an object that represents the instance of the resource. The parameters are defined
as object properties and the like.

#### Namespace
All input/output parameters are put in a namespace, which is usually
the name of the resource.

For example:

    {
        "user": {
            ... parameters ...
        }
    }

### Parameters
There are two parameter types.

#### Data types
The type can be one of:

 - String
 - Boolean
 - Integer
 - Datetime

        "<parameter_name>": {
            "required": true/false/null,
            "label": "Label for this parameter",
            "description": "Describe it's meaning",
            "type": "<one of the data types>",
            "validators": ... validators ...,
            "default": "default value that is used if the parameter is omitted"
        }

#### Resource association
This is used for associations between resources, e.g. car has a wheel.

    "<parameter_name>": {
        "required": true/false/null,
        "label": "Label for this parameter",
        "description": "Describe it's meaning",
        "type": "Resource",
        "resource": ["path", "to", "resource"],
        "value_id": "<name of a parameter that is used as an id>",
        "value_label": "<name of a parameter that is used as a value>",
        "value": {
            "url": "URL to 'show' action of associated resource",
            "method": "HTTP method to use",
            "help": "URL to get the associated resource's 'show' description"
        },
        "choices": {
            "url": "URL to action that returns a list of possible associations",
            "method": "HTTP method to use",
            "help": "URL to description of the list action"
        }
    }

The _resource_ type also has a different output in action response. It returns
a hash containing associated resource ID and its label, so that clients
can show the human-friendly label instead of just an ID.

    "<parameter_name>": {
        "<value of value_id from description>": <resource id>,
        "<value of value_label from description>": "<label>"
    }

### Examples
Examples are described in a generic way, so that every client can
render them according to its syntax.

    {
        "request": {
            ... a hash of request parameters ...
        },
        "response": {
            ... a hash of response parameters ...
        },
        "comment": "Description of the example"
    }

### List API versions
Send request ``OPTIONS /?describe=versions``. The description format:

    {
        "versions": [1, 2, 3, ... list of versions],
        "default": <which version is default>
    }

### Describe default version
Send request ``OPTIONS /?describe=default`` the get the description
of the default version.

### Describe the whole API
It is possible to get self-description of all versions at once.

Send request ``OPTIONS /``. The description format:

    {
        "default_version": <which version is default>,
        "versions": {
            "default": ... full version self-description ...,
            "<version>": ... full version self-description,
             ... all other versions ...
        }
    }

## Authorization
Actions may require different levels of authorization. HaveAPI provides means for
implementing authorization, but it is not self-described.

If the user is authenticated when requesting self-description, only allowed
resources/actions/parameters will be returned.

## Input/output formats
For now, the only supported input format is JSON.

Output format can be chosen by a client. However, no other format than JSON is built-in.
The output format can be chosen with HTTP header ``Accept``.

## Request
Action URL and HTTP method the client learns from the self-description.

Example request:

    POST /users HTTP/1.1
    Content-Type: application/json
    Accept: application/json
    Connection: Close
    
    {
        "user": {
            "login": "mylogin",
            "name": "Very Name",
            "role": "admin"
        }
    }

## Response
Clients know how to interpret the response thanks to the layout type they learn
from the self-description.

Example response to the request above:

    Content-Type: application/json
    
    {
        "user": {
            "id": 1,
            "login": "mylogin",
            "name": "Very Name",
            "role": "admin"
        }
    }
