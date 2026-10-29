import type { DoneCallback } from "./client";

interface HookEntry {
  done: boolean;
  arguments: unknown[];
  callables: DoneCallback[];
}
export interface Hooks {
  debug: number;
  hooks: Record<string, Record<string, HookEntry>>;
  register(type: string, event: string, callback: DoneCallback): void;
  invoke(type: string, event: string, ...args: unknown[]): void;
}
export interface HooksConstructor {
  new (debug?: number): Hooks;
  prototype: Hooks;
}

/**
 * @class Hooks
 * @memberof HaveAPI.Client
 */
export const Hooks = function Hooks(this: Hooks, debug: number) {
  this.debug = debug;
  this.hooks = {};
} as unknown as HooksConstructor;

/**
 * Register a callback for particular event.
 * @method HaveAPI.Client.Hooks#register
 * @param {String} type
 * @param {String} event
 * @param {HaveAPI.Client~doneCallback} callback
 */
Hooks.prototype.register = function (type, event, callback) {
  if (this.debug > 9) console.log("Register callback", type, event);

  if (this.hooks[type] === undefined) this.hooks[type] = {};

  if (this.hooks[type][event] === undefined) {
    if (this.debug > 9) console.log("The event has not occurred yet");

    this.hooks[type][event] = {
      done: false,
      arguments: [],
      callables: [callback],
    };

    return;
  }

  if (this.hooks[type][event].done) {
    if (this.debug > 9)
      console.log("The event has already happened, invoking now");

    // Legacy apply uses the saved array as receiver, with no callback arguments.
    (callback as Function).apply(this.hooks[type][event].arguments);
    return;
  }

  if (this.debug > 9) console.log("The event has not occurred yet, enqueue");

  this.hooks[type][event].callables.push(callback);
};

/**
 * Invoke registered callbacks for a particular event. Callback arguments
 * follow after the two stationary arguments.
 * @method HaveAPI.Client.Hooks#invoke
 * @param {String} type
 * @param {String} event
 */
Hooks.prototype.invoke = function (type, event) {
  var callbackArgs = [];

  if (arguments.length > 2) {
    for (var i = 2; i < arguments.length; i++) callbackArgs.push(arguments[i]);
  }

  if (this.debug > 9) console.log("Invoke callback", type, event, callbackArgs);

  if (this.hooks[type] === undefined) this.hooks[type] = {};

  if (this.hooks[type][event] === undefined) {
    this.hooks[type][event] = {
      done: true,
      arguments: callbackArgs,
      callables: [],
    };
    return;
  }

  this.hooks[type][event].done = true;

  var callables = this.hooks[type][event].callables;

  for (var i = 0; i < callables.length;) {
    (callables.shift() as Function).apply(callbackArgs);
  }
};
