<?php

namespace HaveAPI\Client;

/**
 * A resource in the API.
 */
class Resource implements \ArrayAccess {
	protected $description;
	protected $client;
	protected $name;
	protected $args = array();
	
	/**
	 * @param Client $client
	 * @param string $name resource name
	 * @param \stdClass $description
	 * @param array $args arguments passed from the parent
	 */
	public function __construct($client, $name, $description, $args) {
		$this->client = $client;
		$this->name = $name;
		$this->description = $description;
		$this->args = $args;
	}
	
	/**
	 * Set client instance.
	 * @param Client $c
	 */
	public function setApiClient($c) {
		$this->client = $c;
	}
	
	/**
	 * Set an array of arguments.
	 * @param array $args
	 */
	public function setArguments($args) {;
		$this->args = $args;
	}
	
	/**
	 * @return string resource name
	 */
	public function getName() {
		return $this->name;
	}
	
	/**
	 * @return \stdClass description
	 */
	public function getDescription() {
		return $this->description;
	}
	
	public function offsetExists($offset) {
		
	}
	
	/**
	 * Return child resource or action.
	 * @return mixed
	 */
	public function offsetGet($offset) {
		if(strpos($offset, '.') === false)
			return $this->findObject($offset);
		
		else
			return $this->findNestedObject($offset, $this->description);
		
	}
	
	public function offsetSet($offset, $value) {
		
	}
	
	public function offsetUnset($offset) {
		
	}
	
	public function __toString() {
		return $this->name;
	}
	
	/**
	 * Return child resource or action.
	 * @return mixed
	 */
	public function __get($name) {
		return $this->findObject($name);
	}
	
	/**
	 * Invoke an action and return its response or a resource with provided arguments.
	 * @return mixed
	 */
	public function __call($name, $arguments) {
		$obj = $this->findObject($name);
		
		if($obj instanceof Action)
			return call_user_func_array(array($obj, 'call'), $arguments);
		
		if($obj instanceof Resource) {
			$obj->setArguments(array_merge($this->args, $arguments));
			return $obj;
		}
		
		throw new ActionFailed("'$name' is not an action nor a resource.");
	}
	
	/**
	 * Create a new resource object instance.
	 * @return ResourceInstance
	 */
	public function newInstance() {
		return new ResourceInstance($this->client, $this->create, null);
	}
	
	/**
	 * Find an action or a resource with $name in $description.
	 * @param string name to be found
	 * @param \stdClass description to be searched in
	 */
	protected function findObject($name, $description = null) {
		$this->client->setup();
		
		if(!$description)
			$description = $this->description;
	
		if(isSet($description->actions)) {
			foreach($description->actions as $searched_name => $desc) {
				if($searched_name == $name || in_array($name, $desc->aliases)) {
					return new Action($this->client, $this, $searched_name, $description->actions->$searched_name, $this->args);
				}
			}
		}
		
		if(array_key_exists($name, (array) $description->resources)) {
			return new Resource($this->client, $name, $description->resources->$name, $this->args);
		}
		
		return false;
	}
	
	/**
	 * Find and return an action or a resource which may be nested (names separated by dot).
	 * Used for array access method.
	 * @return mixed
	 */
	protected function findNestedObject($path, $description) {
		$parts = explode('.', $path);
		$ask = $this;
		$len = count($parts);
		
		for($i = 0; $i < $len; $i++) {
			$name = $parts[$i];
			
			$obj = $ask->findObject($name, $description);
			
			if($obj instanceof Resource) {
				$ask = $obj;
				$description = null;
				
			} else if($obj === null) {
				throw new \Exception("Resource or action '$name' not found.");
				
			} else if($obj instanceof Action && $i < $len-1) {
				throw new \Exception("Found action '$name' but path does not end here.");
				
			} else {
				return $obj;
			}
		}
		
		return $ask;
	}
}
