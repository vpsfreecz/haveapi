/**
 * @class Hooks
 * @memberof HaveAPI.Client
 */
var hooks = c.Hooks = function(debug) {
	this.debug = debug;
	this.hooks = {};
};

/**
 * Register a callback for particular event.
 * @method HaveAPI.Client.Hooks#register
 * @param {String} type
 * @param {String} event
 * @param {HaveAPI.Client~doneCallback} callback
 */
hooks.prototype.register = function(type, event, callback) {
	if (this.debug > 9)
		console.log("Register callback", type, event);
	
	if (this.hooks[type] === undefined)
		this.hooks[type] = {};
	
	if (this.hooks[type][event] === undefined) {
		if (this.debug > 9)
			console.log("The event has not occurred yet");
		
		this.hooks[type][event] = {
			done: false,
			arguments: [],
			callables: [callback]
		};
		
		return;
	}
	
	if (this.hooks[type][event].done) {
		if (this.debug > 9)
			console.log("The event has already happened, invoking now");
		
		callback.apply(this.hooks[type][event].arguments);
		return;
	}
	
	if (this.debug > 9)
		console.log("The event has not occurred yet, enqueue");
	
	this.hooks[type][event].callables.push(callback);
};

/**
 * Invoke registered callbacks for a particular event. Callback arguments
 * follow after the two stationary arguments.
 * @method HaveAPI.Client.Hooks#invoke
 * @param {String} type
 * @param {String} event
 */
hooks.prototype.invoke = function(type, event) {
	var callbackArgs = [];
	
	if (arguments.length > 2) {
		for (var i = 2; i < arguments.length; i++)
			callbackArgs.push(arguments[i]);
	}
	
	if (this.debug > 9)
		console.log("Invoke callback", type, event, callbackArgs);
	
	if (this.hooks[type] === undefined)
		this.hooks[type] = {};
	
	if (this.hooks[type][event] === undefined) {
		this.hooks[type][event] = {
			done: true,
			arguments: callbackArgs,
			callables: []
		};
		return;
	}
	
	this.hooks[type][event].done = true;
	
	var callables = this.hooks[type][event].callables;
	
	for (var i = 0; i < callables.length;) {
		callables.shift().apply(callbackArgs);
	}
};
