# Protocol definition
HaveAPI defines the format for the self-description and URLs where the self-description
can be found.

# Self-description
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

# Protocol versioning
Protocol version defines the form and contents of

 - the envelope,
 - API description,
 - data transfers.

Protocol version is in the form `<major>.<minor>`. `major` is incremented
whenever a change is made to the protocol that breaks backward compatibility.
When backward compatibility is kept and only some new features are added to the
protocol, `major` stays and `minor` is incremented.

# Envelope
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

Responses for `OPTIONS` requests also send a protocol version in the envelope:

    "version": <version>

# Description format
In this document, the self-description is encoded in JSON. However, it can
be encoded in any of the supported output formats.

## API version
API version is described as:

    {
        "authentication": {
            ... authentication methods ...
        },
        "resources": {
            ... resources ...
        },
        "meta": {
            "namespace": "_meta"
        },
        "help": "/<version>/"
    }

See appropriate section for detailed description of each section.

## Authentication
HaveAPI defines an interface for implementing custom authentication methods.
HTTP basic and token authentication is built-in.

Authentication methods can be set per API version. They are a part of
the self-description, but must be understood by the client.
The client can choose whichever available authentication method he prefers.

### HTTP basic authentication
HTTP basic authentication needs no other configuration, only informs about its presence.

    "basic": {}

### Token authentication
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
                            "lifetime": ...
                            "interval": ...
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

## Resources
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

## Actions
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
	"meta": ... metadata ...,
        "url": "URL for this action",
        "method": "HTTP method to be used",
        "help": "URL to get this very description of the action"
    }

### Layouts
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

### Namespace
All input/output parameters are put in a namespace, which is usually
the name of the resource.

For example:

    {
        "user": {
            ... parameters ...
        }
    }

## Parameters
There are two parameter types.

### Data types
The type can be one of:

 - String
 - Text
 - Boolean
 - Integer
 - Float
 - Datetime

        "<parameter_name>": {
            "required": true/false/null,
            "label": "Label for this parameter",
            "description": "Describe it's meaning",
            "type": "<one of the data types>",
            "validators": ... validators ...,
            "default": "default value that is used if the parameter is omitted"
        }


#### Validators
Every parameter has its own validators. Any of the following validators
may be present. Input value must pass through all validators in order
to be considered valid.

##### Acceptance
Used when a parameter must have one specific value.

    "accept": {
        "value": <value to accept>,
        "message": "has to be <value>"
    }

##### Presence
The parameter must be present. If `empty` is `false`, leading and trailing
whitespace is stripped before the check.

    "present": {
        empty: true/false,
        message: "must be present"
    }

##### Confirmation
Used to confirm that two parameters have either the same value or not have the
same value. The former can be used e.g. to verify that passwords are same
and the latter to give two different e-mail addresses.

    "confirm": {
        "equal": true/false,
        "parameter": <parameter_name>,
        "message": "must (or must not) be the same as <parameter_name>"
    }

##### Inclusion
The parameter can contain only one of given options.

    "include": {
        "values": ["list", "of", "allowed", "values"],
        "message": "%{value} cannot be used"
    }

If the `values` are a list, than it is a list of accepted values.
If the `values` are a hash, the keys of that hash are accepted values,
values in that hash are to be shown in UI.

    "include": {
        "values": {
            "one": "Fancy one",
            "two": "Fancy two"
        },
        "message": "%{value} cannot be used"
    }

##### Exclusion
The parameter can be set to anything except values listed here.

    "exclude": {
        "values": ["list", "of", "excluded", "values"],
        "message": "%{value} cannot be used"
    }

##### Specific format
If `match` is true, the parameter must pass given regular expression.
Otherwise it must not pass the regular expression.

    "format": {
        "rx": "regular expression",
        "match": true/false,
	"description": "human-readable description of the regular expression",
        "message": "%{value} is not in a valid format"
    }

##### Length
Useful only for `String` and `Text` parameters. Checks the length of given string.
It may check either

 - minimum
 - maximum
 - minimum and maximum
 - constant length

The length validator must therefore contain one or more checks, but cannot
contain both min/max and equality.

Length range:

    "length": {
        "min": 0,
        "max": 99,
        "message": "length has to be in range <0,99>"
    }

Constant length:

    "length": {
        "equals": 10,
        "message": "length has to be 10"
    }

##### Numericality
Numericality implies that the parameter must be a number, i.e. `Integer`, `Float`
or `String` containing only digits. It can check that the number is in a specified
range and can provide a step. The validator can contain one or more of these conditions.

    "number": {
        "min": 0,
        "max": 99,
        "step": 3,
        "mod": 3,
        "even": true/false,
        "odd": true/false
    }

##### Custom validation
Custom validation cannot be documented by the API. The developer may or may not
provide information that some non-documented validation takes place. The documentation
contains only the description of the validations that may be shown to the user,
but is not evaluated client-side, only server-side.

    "custom": "description of custom validation"

### Resource association
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

## Examples
Examples are described in a generic way, so that every client can
render them according to its syntax.

    {
        "title": "A title",
        "request": {
            ... a hash of request parameters ...
        },
        "response": {
            ... a hash of response parameters ...
        },
        "comment": "Description of the example"
    }

## Metadata
Metadata can be global and per-object. Global metadata are sent once for each
response, where as per-object are sent with each object that is a part of the
response.

    {
        "global": {
            "input": ... parameters or null ...,
            "output: ... parameters or null ...
        } or null,
        
        "object": {
            "input": ... parameters or null ...,
            "output: ... parameters or null ...
        } or null,
    }

## List API versions
Send request ``OPTIONS /?describe=versions``. The description format:

    {
        "versions": [1, 2, 3, ... list of versions],
        "default": <which version is default>
    }

## Describe default version
Send request ``OPTIONS /?describe=default`` the get the description
of the default version.

## Describe the whole API
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

# Authorization
Actions may require different levels of authorization. HaveAPI provides means for
implementing authorization, but it is not self-described.

If the user is authenticated when requesting self-description, only allowed
resources/actions/parameters will be returned.

# Input/output formats
For now, the only supported input format is JSON.

Output format can be chosen by a client. However, no other format than JSON is built-in.
The output format can be chosen with HTTP header ``Accept``.

# Request
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

# Response
Clients know how to interpret the response thanks to the layout type they learn
from the self-description.

Example response to the request above:

    Content-Type: application/json
    
    {
        "status": true,
        "response": {
            "user": {
                "id": 1,
                "login": "mylogin",
                "name": "Very Name",
                "role": "admin"
            }
        },
        "message": null,
        "errors: null
    }
