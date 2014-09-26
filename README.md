haveapi-client-php
==================

haveapi-client-php is a PHP client for [HaveAPI](https://github.com/vpsfreecz/haveapi) based APIs.

Requirements
------------
 - PHP >= 5.3
 - [Httpful](http://phphttpclient.com/)

Installation
------------
haveapi-client-php can be installed with composer, add `haveapi/client` to your `composer.json`:

	{
		"require": {
			"haveapi/client": "*"
		}
	}

You can also clone this repository and use a PSR-4 compatible autoloader, or include
`bootstrap.php`, which loads all necessary classes. When using the repository, you
have to install Httpful yourself.

Usage
-----

First check out the API documentation, see how it works and what resources/actions
are available.

Create a client instance:

	$api = new \HaveAPI\Client("http://your.api.tld");

Authenticate with HTTP basic:

	$api->authenticate('basic', ['username' => 'yourname', 'password' => 'password']);

Authenticate with token:

	$api->authenticate('token', ['username' => 'yourname', 'password' => 'password']);

When using the token authentication, it is usually necessary to save the token for later use:

	$token = $api->authenticationProvider()->getToken();

Next time, authenticate with the previously received token:

	$api->authenticate('token', ['token' => $token]);

Resources and actions can be accessed using two methods.

### Access as array indexes

	$api['vps']['index']->call();
	$api['vps']['show']->call(101);

or

	$api['vps.index']->call();
	$api['vps.show']->call(101);

### Access as properties/methods

	$api->vps->list();

Arguments can be supplied to resources and/or to the action.

	$api->vps->find(101);
	$api->vps->ip_address->delete(101, 10);

	$api->vps(101)->find();
	$api->vps(101)->ip_address(10)->delete();
	$api->vps(101)->ip_address->delete(10);

### Parameters
Parameters are given as an array to action. It is the last argument given to action.
Object IDs must be in front of it.

	$api->vps->create([
		'hostname' => 'myhostname',
		'template' => 1
	]);

	$api->vps->ip_address->create(101, array('version' => 4));
	$api->vps(101)->ip_address->create(array('version' => 4));

### Object-like behaviour
Fetch existing resource:

	$vps = $api->vps->find(101);
	echo $vps->id . "<br>";
	echo $vps->hostname . "<br>";
	$vps->hostname = 'gotcha';
	$vps->save();

Create a new instance:

	$vps = $api->vps->newInstance();
	$vps->hostname = 'new vps';
	$vps->save();
	echo $vps->id . "<br>";

List of resources:

	$vpses = $api->vps->list();
	
	foreach($vpses as $vps) {
		echo $vps->id ." = ". $vps->hostname ."<br>";
	}

### Response
If the action does not return object or object list, `\HaveAPI\Client\Response` class is returned instead.

	$vps = $api->vps->find(101);
	$response = $vps->custom_action();
	
	print_r($response->getResponse());

Parameters can be accessed directly as:

	echo $response['hostname'];

### Error handling
If an action fails, exception `\HaveAPI\Client\Exception\ActionFailed` is thrown. Authentication errors
result in exception `\HaveAPI\Client\Exception\AuthenticationFailed`.

	try {
		$api->vps->create();
		
	} catch(\HaveAPI\ActionFailed $e) {
		echo $e->getMessage();
		print_r($e->getErrors());
	}

License
-------
haveapi-client-php is released under the MIT license.
