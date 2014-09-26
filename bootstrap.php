<?php

$classes = array(
	'Client/AuthenticationProviders/Base',
	'Client/AuthenticationProviders/NoAuth',
	'Client/AuthenticationProviders/Basic',
	'Client/AuthenticationProviders/Token',
	'Client/Exception/ActionFailed',
	'Client/Exception/AuthenticationFailed',
	'Client/Action',
	'Client/Resource',
	'Client/ResourceInstance',
	'Client/ResourceInstanceList',
	'Client/Response',
	'Client'
);

foreach($classes as $class) {
	include "src/$class.php";
}
