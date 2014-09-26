<?php

namespace HaveAPI\Client\AuthenticationProviders;

/**
 * Provider for token authentication.
 *
 * Accepts either a `token` or `username` and `password` to acquire a token.
 * Option `via` determines how the token is sent to the API. It defaults
 * to TokenAuth::HTTP_HEADER.
 */
class Token extends Base {
	const HTTP_HEADER = 0;
	const QUERY_PARAMETER = 1;
	
	private $rs;
	private $configured = false;
	private $token;
	private $validTo = null;
	private $via;
	
	/**
	 * Request a new token if it isn't in the options.
	 */
	protected function setup() {
		$this->rs = new \HaveAPI\Client\Resource($this->client, 'token', $this->description->resources->token, array());
		$this->via = isSet($this->opts['via']) ? $this->opts['via'] : self::HTTP_HEADER;
		
		if(isSet($this->opts['token'])) {
			$this->configured = true;
			$this->token = $this->opts['token'];
			return;
		}
		
		$this->requestToken();
	}
	
	/**
	 * Add token header if configured. Checks token validity.
	 */
	public function authenticate($request) {
		if(!$this->configured)
			return;
		
		$this->checkValidity();
		
		if($this->via == self::HTTP_HEADER)
			$request->addHeader($this->description->http_header, $this->token);
	}
	
	/**
	 * Returns token query parameter if configured.
	 */
	public function queryParameters() {
		if(!$this->configured || $this->via != self::QUERY_PARAMETER)
			return array();
		
		return array($this->description->query_parameter => $this->token);
	}
	
	/**
	 * Revoke the token.
	 */
	public function logout() {
		$this->rs->revoke();
	}
	
	/**
	 * Request a new token from the API.
	 */
	protected function requestToken() {
		$ret = $this->rs->request(array(
			'login' => $this->opts['username'],
			'password' => $this->opts['password'],
			'lifetime' => $this->translateLifetime(isSet($this->opts['lifetime']) ? $this->opts['lifetime'] : 'renewable_auto'),
			'interval' => isSet($this->opts['interval']) ? $this->opts['interval'] : 300
		));
		
		$this->token = $ret->response()->token;
		
		$v = $ret->response()->valid_to;
		
		if($v)
			$this->validTo = strtotime($v);
		
		$this->configured = true;
	}
	
	/**
	 * Get a new token if the current one expired.
	 */
	protected function checkValidity() {
		if($this->validTo && $this->validTo < time() && isSet($this->opts['username']) && isSet($this->opts['password']))
			$this->requestToken();
	}
	
	/**
	 * @return string the token
	 */
	public function getToken() {
		return $this->token;
	}
	
	/**
	 * @return int expiration time
	 */
	public function getValidTo() {
		return $this->validTo;
	}
	
	private function translateLifetime($lifetime) {
		$options = array('fixed', 'renewable_manual', 'renewable_auto', 'permanent');
		return array_search($lifetime, $options);
	}
}
