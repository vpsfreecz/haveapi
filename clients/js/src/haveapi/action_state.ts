import type { ActionCall } from './action';

export interface ActionStateData {
	id: number;
	label?: string;
	finished?: boolean;
	status?: boolean;
	created_at?: string | null;
	updated_at?: string | null;
	can_cancel?: boolean;
	current?: number;
	total?: number;
	unit?: string;
}
export interface Progress {
	current: number | undefined;
	total: number | undefined;
	unit: string | undefined;
	toString(): string;
}
export interface ProgressConstructor {new(state: ActionStateData): Progress; prototype: Progress;}
export interface ActionState {
	id: number;
	label: string | undefined;
	finished: boolean | undefined;
	status: boolean | undefined;
	createdAt: Date | string | null | undefined;
	updatedAt: Date | string | null | undefined;
	canCancel: boolean | undefined;
	progress: Progress;
	doStop?: boolean;
	doCancel?: boolean;
	cancelOpts?: ActionCall;
	stop(): void;
	shouldStop(): boolean;
	cancel(opts?: ActionCall): void;
	shouldCancel(): boolean;
}
export interface ActionStateConstructor {
	new(state: ActionStateData): ActionState;
	prototype: ActionState;
	Progress: ProgressConstructor;
}


/**
 * @class ActionState
 * @memberof HaveAPI.Client
 */
export const ActionState = function ActionState(this: ActionState, state: ActionStateData) {
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
	this.progress = new (ActionState as unknown as ActionStateConstructor).Progress(state);
} as unknown as ActionStateConstructor;

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
ActionState.prototype.cancel = function (opts?: ActionCall) {
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
ActionState.Progress = function Progress(this: Progress, state: ActionStateData) {
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
} as unknown as ProgressConstructor;

/**
 * @method HaveAPI.Client.ActionState.Progress#toString
 * @return {String}
 */
ActionState.Progress.prototype.toString = function () {
	return this.current + "/" + this.total + " " + this.unit;
};
