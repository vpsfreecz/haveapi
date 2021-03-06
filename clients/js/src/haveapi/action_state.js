/**
 * @class ActionState
 * @memberof HaveAPI.Client
 */
function ActionState (state) {
	/**
	 * @member {Integer} HaveAPI.Client.ActionState#id
	 * @readonly
	 */
	this.id = state.id;

	/**
	 * @member {String} HaveAPI.Client.ActionState#label
	 * @readonly
	 */
	this.label = state.label;

	/**
	 * @member {Boolean} HaveAPI.Client.ActionState#finished
	 * @readonly
	 */
	this.finished = state.finished;

	/**
	 * @member {Boolean} HaveAPI.Client.ActionState#status
	 * @readonly
	 */
	this.status = state.status;

	/**
	 * @member {Date} HaveAPI.Client.ActionState#createdAt
	 * @readonly
	 */
	this.createdAt = state.created_at && new Date(state.created_at);

	/**
	 * @member {Date} HaveAPI.Client.ActionState#updatedAt
	 * @readonly
	 */
	this.updatedAt = state.updated_at && new Date(state.updated_at);

	/**
	 * @member {Boolean} HaveAPI.Client.ActionState#canCancel
	 * @readonly
	 */
	this.canCancel = state.can_cancel;

	/**
	 * @member {HaveAPI.Client.ActionState.Progress} HaveAPI.Client.ActionState#progress
	 * @readonly
	 */
	this.progress = new ActionState.Progress(state);
};

/**
 * Stop tracking of this action state
 * @method HaveAPI.Client.ActionState#stop
 */
ActionState.prototype.stop = function () {
	this.doStop = true;
};

/**
 * @method HaveAPI.Client.ActionState#shouldStop
 */
ActionState.prototype.shouldStop = function () {
	return this.doStop || false;
};

/**
 * Cancel execution of this action. Action can be cancelled only if
 * {@link HaveAPI.Client.ActionState#canCancel}  is `true`, otherwise exception
 * {@link HaveAPI.Client.Exceptions.UncancelableAction} is thrown.
 *
 * Note that the cancellation can be a blocking action, so you can pass standard callback
 * functions.
 *
 * @method HaveAPI.Client.ActionState#cancel
 * @param {HaveAPI.Client~ActionCall} opts
 */
ActionState.prototype.cancel = function (opts) {
	this.doCancel = true;
	this.cancelOpts = opts;
};

/**
 * @method HaveAPI.Client.ActionState#shouldCancel
 */
ActionState.prototype.shouldCancel = function () {
	return this.doCancel || false;
};

/**
 * @class HaveAPI.Client.ActionState.Progress
 * @memberof HaveAPI.Client.ActionState
 */
ActionState.Progress = function (state) {
	/**
   * @member {Integer} HaveAPI.Client.ActionState.Progress#current
	 * @readonly
	 */
	this.current = state.current;

	/**
	 * @member {Integer} HaveAPI.Client.ActionState.Progress#total
	 * @readonly
	 */
	this.total = state.total;

	/**
	 * @member {String} HaveAPI.Client.ActionState.Progress#unit
	 * @readonly
	 */
	this.unit = state.unit;
};

/**
 * @method HaveAPI.Client.ActionState.Progress#toString
 * @return {String}
 */
ActionState.Progress.prototype.toString = function () {
	return this.current + "/" + this.total + " " + this.unit;
};
