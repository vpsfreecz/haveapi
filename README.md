vpsadminctl-php
===============

vpsadminctl-php is a PHP client for vpsAdmin API.

Requirements
------------
 - PHP >= 5.4
 - [Httpful](http://phphttpclient.com/) - already included in `vendor/`

Usage
-----

First check out API documentation, see how it works and what resources/actions
are available.

Include client:

	<?php
	include 'vpsadmin.php';

`vpsadmin.php` includes Httpful from `vendor/`.

Create client instance:

	$api = new \VpsAdmin\Client();

Authenticate with HTTP basic auth:

	$api->login('yourname', 'password');

Resources and actions can be accessed using two methods.

### Access as array indexes

	$api['vps']['index']->call();
	$api['vps']['show']->call(101);

or

	$api['vps.index']->call();
	$api['vps.show']->call(101);

### Access as properties/methods

	$api->vps->index();

Arguments can be supplied to resources and/or to the action.

	$api->vps->show(101);
	$api->vps->ip_address->delete(101, 10);

	$api->vps(101)->show();
	$api->vps(101)->ip_address(10)->delete();
	$api->vps(101)->ip_address->delete(10);

### Parameters
Parameters are given as an array to action. It is the last argument given to action.
Object IDs must be in front of it.

	$api->vps->create([
		'hostname' => 'myhostname',
		'template_id' => 1
	]);

	$api->vps->ip_address->create(101, ['version' => 4]);
	$api->vps(101)->ip_address->create(['version' => 4]);

### Response
Action returns `Response` object. It has several helper methods.

	$response = $api->vps->index();
	
	// Check if action succeeded
	if($response->isOk()) { // Succeeded
		
		// Print received data
		// This method raises an exception if action failed
		print_r($response->response());
		
	} else { // Action failed
		
		// See what/why failed
		echo "Action failed: ". $response->message(); 
		
		// Print errors
		print_r($response->errors());
	}

License
-------
vpsadminctl-php is released under GNU/GPL.
