/**
 * @namespace HaveAPI
 * @author Jakub Skokan <jakub.skokan@vpsfree.cz>
 **/

// Register built-in providers
Authentication.registerProvider('basic', Authentication.Basic);
Authentication.registerProvider('token', Authentication.Token);

classes = [
	'Action',
	'Authentication',
	'BaseResource',
	'Hooks',
	'Http',
	'Resource',
	'ResourceInstance',
	'ResourceInstanceList',
	'Response',
]

for (var i = 0; i < classes.length; i++)
	Client[ classes[i] ] = eval(classes[i]);

var HaveAPI = {
	Client: Client
};
