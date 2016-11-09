/**
 * @namespace HaveAPI
 * @author Jakub Skokan <jakub.skokan@vpsfree.cz>
 **/

var XMLHttpRequest;

if (typeof exports === 'object' && (typeof window === 'undefined' || !window.XMLHttpRequest)) {
	XMLHttpRequest = require('xmlhttprequest').XMLHttpRequest;

} else {
	XMLHttpRequest = window.XMLHttpRequest;
}

// Register built-in providers
Authentication.registerProvider('basic', Authentication.Basic);
Authentication.registerProvider('token', Authentication.Token);

var classes = [
	'Action',
	'Authentication',
	'BaseResource',
	'Hooks',
	'Http',
	'Resource',
	'ResourceInstance',
	'ResourceInstanceList',
	'Response',
	'LocalResponse',
];

for (var i = 0; i < classes.length; i++)
	Client[ classes[i] ] = eval(classes[i]);

var HaveAPI = {
	Client: Client
};
