<?php

namespace HaveAPI\Client;

/**
 * Response from the API.
 */
class Response implements \ArrayAccess {
	private $action;
	private $envelope;
	private $time;
	
	/**
	 * @param Action $action
	 * @param \Httpful\Response $response envelope received response
	 * @param float $time time spent communicating with the API
	 */
	public function __construct($action, $response, $time) {
		if($response->code == 401)
			throw new Exception\AuthenticationFailed($response->body->message);
		
		$this->action = $action;
		$this->envelope = $response->body;
		$this->time = $time;
	}
	
	/**
	 * @return boolean
	 */
	public function isOk() {
		return $this->envelope->status;
	}
	
	/**
	 * @return string
	 */
	public function getMessage() {
		return $this->envelope->message;
	}
	
	/**
	 * For known layouts, namespaced response is returned, or else the data is returned as is.
	 * @return \stdClass
	 */
	public function getResponse() {
		$l = $this->action->layout('output');
		
		switch($l) {
			case 'object':
			case 'object_list':
			case 'hash':
			case 'hash_list':
				return $this->envelope->response->{$this->action->getNamespace('output')};
				
			default:
				return $this->envelope->response;
		}
	}
	
	/**
	 * @return \stdClass
	 */
	public function getErrors() {
		return $this->envelope->errors;
	}
	
	public function __toString() {
		return json_encode($this->getResponse());
	}
	
	/**
	 * Return time spent communicating with the API to get this response.
	 * @return float spent time
	 */
	public function getSpentTime() {
		return $this->time;
	}
	
	// ArrayAccess
	public function offsetExists($offset) {
		$r = $this->getResponse();
		
		return isSet($r->{$offset});
	}
	
	public function offsetGet($offset) {
		$r = $this->getResponse();
		
		return $r->{$offset};
	}
	
	public function offsetSet($offset, $value) {
		$r = $this->getResponse();
		
		$r->{$offset} = $value;
	}
	
	public function offsetUnset($offset) {
		$r = $this->getResponse();
		
		unset($r->{$offset});
	}
}
