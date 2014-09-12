haveapi-client-php
==================

haveapi-client-php is a PHP client for HaveAPI based APIs.

Requirements
------------
 - PHP >= 5.3
 - [Httpful](http://phphttpclient.com/) - already included in `vendor/`

Usage
-----

First check out API documentation, see how it works and what resources/actions
are available.

Include client:

	<?php
	include 'haveapi.php';

`haveapi.php` includes Httpful from `vendor/`, `haveapi_client.php` does not.

Create a client instance:

	$api = new \HaveAPI\Client("http://your.api.tld");

Authenticate with HTTP basic:

	$api->authenticate('basic', ['username' => 'yourname', 'password' => 'password']);

Authenticate with token:

	$api->authenticate('token', ['username' => 'yourname', 'password' => 'password']);

or

	$api->authenticate('token', ['token' => 'abcedfghijklmopqrstuvxyz']);

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

Create new instance:

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
If the action does not return object or object list, `\HaveAPI\Response` class is returned instead.

	$vps = $api->vps->find(101);
	$response = $vps->custom_action();
	
	print_r($response->response());

Parameters can be accessed directly as:

	echo $response['hostname'];

### Error handling
If an action fails, exception `\HaveAPI\ActionFailed` is thrown. Authentication errors
result in exception `\HaveAPI\AuthenticationFailed`.

	try {
		$api->vps->create();
		
	} catch(\HaveAPI\ActionFailed $e) {
		echo $e->getMessage();
		print_r($e->errors());
	}

License
-------
haveapi-client-php is released under the MIT license.
