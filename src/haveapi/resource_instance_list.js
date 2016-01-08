/**
 * Arguments are the same as for {@link HaveAPI.Client.ResourceInstance}.
 * @class ResourceInstanceList
 * @classdesc Represents a list of {@link HaveAPI.Client.ResourceInstance} objects.
 * @see {@link HaveAPI.Client.ResourceInstance}
 * @memberof HaveAPI.Client
 */
function ResourceInstanceList (client, action, response) {
	this.response = response;
	
	/**
	 * @member {Array} HaveAPI.Client.ResourceInstanceList#items An array containg all items.
	 */
	this.items = [];
	
	var ret = response.response();
	
	/**
	 * @member {integer} HaveAPI.Client.ResourceInstanceList#length Number of items in the list.
	 */
	this.length = ret.length;
	
	/**
	 * @member {integer} HaveAPI.Client.ResourceInstanceList#totalCount Total number of items available.
	 */
	this.totalCount = response.meta().total_count;
	
	for (var i = 0; i < this.length; i++)
		this.items.push(new Client.ResourceInstance(client, action, ret[i], false, true));
};

/**
 * @callback HaveAPI.Client.ResourceInstanceList~iteratorCallback
 * @param {HaveAPI.Client.ResourceInstance} object
 */

/**
 * A shortcut to {@link HaveAPI.Client.Response#isOk}.
 * @method HaveAPI.Client.ResourceInstanceList#isOk
 * @return {Boolean}
 */
ResourceInstanceList.prototype.isOk = function() {
	return this.response.isOk();
};

/**
 * Return the response that this instance is created from.
 * @method HaveAPI.Client.ResourceInstanceList#apiResponse
 * @return {HaveAPI.Client.Response}
 */
ResourceInstanceList.prototype.apiResponse = function() {
	return this.response;
};

/**
 * Call fn for every item in the list.
 * @param {HaveAPI.Client.ResourceInstanceList~iteratorCallback} fn
 * @method HaveAPI.Client.ResourceInstanceList#each
 */
ResourceInstanceList.prototype.each = function(fn) {
	for (var i = 0; i < this.length; i++)
		fn( this.items[ i ] );
};

/**
 * Return item at index.
 * @method HaveAPI.Client.ResourceInstanceList#itemAt
 * @param {Integer} index
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstanceList.prototype.itemAt = function(index) {
	return this.items[ index ];
};

/**
 * Return first item.
 * @method HaveAPI.Client.ResourceInstanceList#first
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstanceList.prototype.first = function() {
	if (this.length == 0)
		return null;
	
	return this.items[0];
};

/**
 * Return last item.
 * @method HaveAPI.Client.ResourceInstanceList#last
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstanceList.prototype.last = function() {
	if (this.length == 0)
		return null;
	
	return this.items[ this.length - 1 ]
};
