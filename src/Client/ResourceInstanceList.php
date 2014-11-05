<?php

namespace HaveAPI\Client;

/**
 * A list of resource object instances.
 */
class ResourceInstanceList implements \ArrayAccess, \Iterator {
	private $items = array();
	private $index = 0;
	private $response;
	
	/**
	 * @param Client $client
	 * @param Action $action
	 * @param Response $response
	 */
	public function __construct($client, $action, $response) {
		$this->response = $response;
		
		foreach($response->getResponse() as $item) {
			$this->items[] = new ResourceInstance($client, $action, $item);
		}
	}
	
	/**
	 * @return int object count
	 */
	public function count() {
		return count($this->items);
	}
	
	/**
	 * @return Response
	 */
	public function getApiResponse() {
		return $this->response;
	}
	
	/**
	 * @return ResourceInstance first object
	 */
	public function first() {
		return $this->items[0];
	}
	
	/**
	 * @return ResourceInstance last object
	 */
	public function last() {
		return $this->items[ $this->count() - 1 ];
	}
	
	/**
	 * Returns all objects in an array.
	 * @return array
	 */
	public function asArray() {
		return $this->items;
	}
	
	public function getMeta() {
		return $this->response->getMeta();
	}
	
	public function getTotalCount() {
		$m = $this->getMeta();
		
		if (!$m || !isset($m->total_count))
			return false;
		
		return $m->total_count;
	}
	
	// ArrayAccess
	public function offsetExists($offset) {
		return isSet($this->items[$offset]);
	}
	
	public function offsetGet($offset) {
		return $this->items[$offset];
	}
	
	public function offsetSet($offset, $value) {
		$this->items[$offset] = $value;
	}
	
	public function offsetUnset($offset) {
		unset($this->items[$offset]);
	}
	
	// Iterator
	public function current() {
		return $this->items[$this->index];
	}
	
	public function key() {
		return $this->index;
	}
	
	public function next() {
		++$this->index;
	}
	
	public function rewind() {
		$this->index = 0;
	}
	
	public function valid() {
		return isSet($this->items[$this->index]);
	}
}
