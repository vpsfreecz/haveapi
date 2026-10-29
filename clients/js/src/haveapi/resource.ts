import { BaseResource } from "./base_resource";
import { Client } from "./client";
import type { BaseResourcePrivate } from "./base_resource";
import type { InvocationArgument } from "./action";
import type { ResourceDescription } from "./types";
import type { ResourceInstance } from "./resource_instance";

export interface ResourcePrivate extends BaseResourcePrivate {
  args: InvocationArgument[];
}
export interface Resource extends BaseResource<ResourcePrivate> {
  (...args: InvocationArgument[]): Resource;
  applyArguments(args: InvocationArgument[]): Resource;
  "new"(): ResourceInstance;
}
export interface ResourceConstructor {
  new (
    client: Client,
    parent: BaseResource | null,
    name: string,
    description: ResourceDescription,
    args: InvocationArgument[],
  ): Resource;
  prototype: Resource;
}

/**
 * @class Resource
 * @memberof HaveAPI.Client
 */
export const Resource = function Resource(
  this: Resource,
  client: Client,
  parent: BaseResource | null,
  name: string,
  description: ResourceDescription,
  args: InvocationArgument[],
) {
  this._private = {
    client: client,
    parent: parent,
    name: name,
    description: description,
    args: args,
  };

  this.attachResources(description, args);
  this.attachActions(description, args);

  var that = this;
  var fn = function () {
    return new (Resource as unknown as ResourceConstructor)(
      that._private.client,
      that._private.parent,
      that._private.name,
      that._private.description,
      that._private.args.concat(Array.prototype.slice.call(arguments)),
    );
  };
  (fn as unknown as { __proto__: Resource }).__proto__ = this;

  return fn;
} as unknown as ResourceConstructor;

Resource.prototype = new BaseResource() as Resource;

// Unused
Resource.prototype.applyArguments = function (args: InvocationArgument[]) {
  for (var i = 0; i < args.length; i++) {
    this._private.args.push(args[i]);
  }

  return this;
};

/**
 * Return a new, empty resource instance.
 * @method HaveAPI.Client.Resource#new
 * @return {HaveAPI.Client.ResourceInstance} resource instance
 */
Resource.prototype.new = function () {
  // Preserve the legacy helper's direct-property lookup, including absent fields.
  var legacy = this as unknown as {
    client: Client;
    parent: BaseResource | null;
    create: import("./action").Action;
  };
  return new Client.ResourceInstance(
    legacy.client,
    legacy.parent,
    legacy.create,
    null,
    false,
  );
};
