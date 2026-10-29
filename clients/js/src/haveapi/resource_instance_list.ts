import { Client } from "./client";
import type { Action } from "./action";
import type { ResourceInstance } from "./resource_instance";
import type { Response } from "./response";
import type { Values } from "./types";

export interface ResourceInstanceList {
  response: Response;
  items: ResourceInstance[];
  length: number;
  totalCount: unknown;
  isOk(): boolean;
  apiResponse(): Response;
  each(fn: (item: ResourceInstance) => void): void;
  itemAt(index: number): ResourceInstance | undefined;
  first(): ResourceInstance | null;
  last(): ResourceInstance | null;
}
export interface ResourceInstanceListConstructor {
  new (
    client: Client,
    action: Action,
    response: Response,
  ): ResourceInstanceList;
  prototype: ResourceInstanceList;
}

/**
 * Arguments are the same as for {@link HaveAPI.Client.ResourceInstance}.
 * @class ResourceInstanceList
 * @classdesc Represents a list of {@link HaveAPI.Client.ResourceInstance} objects.
 * @see {@link HaveAPI.Client.ResourceInstance}
 * @memberof HaveAPI.Client
 */
export const ResourceInstanceList = function ResourceInstanceList(
  this: ResourceInstanceList,
  client: Client,
  action: Action,
  response: Response,
) {
  this.response = response;

  /**
   * @member {Array} HaveAPI.Client.ResourceInstanceList#items An array containg all items.
   */
  this.items = [];

  var ret = response.response() as Values[] | null | undefined;

  /**
   * @member {integer} HaveAPI.Client.ResourceInstanceList#length Number of items in the list.
   */
  this.length = ret ? ret.length : 0;

  /**
   * @member {integer} HaveAPI.Client.ResourceInstanceList#totalCount Total number of items available.
   */
  this.totalCount = response.meta().total_count;

  for (var i = 0; i < this.length; i++)
    this.items.push(
      new Client.ResourceInstance(
        client,
        action.resource._private.parent,
        action,
        ret![i],
        false,
        true,
      ),
    );
} as unknown as ResourceInstanceListConstructor;

/**
 * @callback HaveAPI.Client.ResourceInstanceList~iteratorCallback
 * @param {HaveAPI.Client.ResourceInstance} object
 */

/**
 * A shortcut to {@link HaveAPI.Client.Response#isOk}.
 * @method HaveAPI.Client.ResourceInstanceList#isOk
 * @return {Boolean}
 */
ResourceInstanceList.prototype.isOk = function () {
  return this.response.isOk();
};

/**
 * Return the response that this instance is created from.
 * @method HaveAPI.Client.ResourceInstanceList#apiResponse
 * @return {HaveAPI.Client.Response}
 */
ResourceInstanceList.prototype.apiResponse = function () {
  return this.response;
};

/**
 * Call fn for every item in the list.
 * @param {HaveAPI.Client.ResourceInstanceList~iteratorCallback} fn
 * @method HaveAPI.Client.ResourceInstanceList#each
 */
ResourceInstanceList.prototype.each = function (
  fn: (item: ResourceInstance) => void,
) {
  for (var i = 0; i < this.length; i++) fn(this.items[i]);
};

/**
 * Return item at index.
 * @method HaveAPI.Client.ResourceInstanceList#itemAt
 * @param {Integer} index
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstanceList.prototype.itemAt = function (index: number) {
  return this.items[index];
};

/**
 * Return first item.
 * @method HaveAPI.Client.ResourceInstanceList#first
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstanceList.prototype.first = function () {
  if (this.length == 0) return null;

  return this.items[0];
};

/**
 * Return last item.
 * @method HaveAPI.Client.ResourceInstanceList#last
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstanceList.prototype.last = function () {
  if (this.length == 0) return null;

  return this.items[this.length - 1];
};
