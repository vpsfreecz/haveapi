<?php

namespace HaveAPI\Client\Exception;

/**
 * Thrown when an action fails.
 */
class ActionFailed extends \Exception {
	private $response;
	
	public function __construct($response, $message, $code = 0, $previous = null) {
		$this->response = $response;
		
		parent::__construct($message, $code, $previous);
	}
	
	/**
	 * Return an array of errors.
	 * @return array
	 */
	public function errors() {
		return $this->response->errors();
	}
}
