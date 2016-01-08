/**
 * @class Http
 * @memberof HaveAPI.Client
 */
function Http (debug) {
	this.debug = debug;
};

/**
 * @callback HaveAPI.Client.Http~replyCallback
 * @param {Integer} status received HTTP status code
 * @param {Object} response received response
 */

/**
 * @method HaveAPI.Client.Http#request
 */
Http.prototype.request = function(opts) {
	if (this.debug > 5)
		console.log("Request to " + opts.method + " " + opts.url);
	
	var r = new XMLHttpRequest();
	
	if (opts.credentials === undefined)
		r.open(opts.method, opts.url);
	else
		r.open(opts.method, opts.url, true, opts.credentials.username, opts.credentials.password);
	
	for (var h in opts.headers) {
		r.setRequestHeader(h, opts.headers[h]);
	}
	
	if (opts.params !== undefined)
		r.setRequestHeader('Content-Type', 'application/json; charset=utf-8');
	
	r.onreadystatechange = function() {
		var state = r.readyState;
		
		if (this.debug > 6)
			console.log('Request state is ' + state);
		
		if (state == 4 && opts.callback !== undefined) {
			opts.callback(r.status, JSON.parse(r.responseText));
		}
	};
	
	if (opts.params !== undefined) {
		r.send(JSON.stringify( opts.params ));
		
	} else {
		r.send();
	}
};
