<?php

namespace HaveAPI\Client;

/**
 * Response from the API.
 */
class Response implements \ArrayAccess {
	private $action;
	private $envelope;
	
	/**
	 * @param Action $action
	 * @param \Httpful\Response envelope received response
	 */
	public function __construct($action, $response) {
		if($response->code == 401)
			throw new Exception\AuthenticationFailed($response->body->message);
		
		$this->action = $action;
		$this->envelope = $response->body;
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
		return json_encode($this->response());
	}
	
	// ArrayAccess
	public function offsetExists($offset) {
		$r = $this->response();
		
		return isSet($r->{$offset});
	}
	
	public function offsetGet($offset) {
		$r = $this->response();
		
		return $r->{$offset};
	}
	
	public function offsetSet($offset, $value) {
		$r = $this->response();
		
		$r->{$offset} = $value;
	}
	
	public function offsetUnset($offset) {
		$r = $this->response();
		
		unset($r->{$offset});
	}
}
