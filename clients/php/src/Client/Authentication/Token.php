<?php

namespace HaveAPI\Client\Authentication;
use HaveAPI\Client\Resource;
use Httpful\Request;

/**
 * Provider for token authentication.
 *
 * The provider can either ask for a new token or use an existing token. To
 * ask for a new token, the provider needs to be given credentials for action
 * `Request`. These default to `user` and `password`, but can be arbitrary.
 *
 * The API may require multi-step authentication, in which case the provider
 * will invoke callback function passed via option `callback`. The callback
 * is called with three arguments: the action name, intermediate token
 * and an array with action input parameters and their description. The callback
 * then returns an array with input parameter values, or string `stop` to stop
 * the authentication process.
 *
 * The authentication process can be later resumed by passing option `resume`.
 * It is an array with three keys: `action` identifying the authentication
 * action to resume with, `token` containing the intermediate authentication
 * token and `input` with input parameters (credentials).
 *
 * Option `via` determines how the token is sent to the API. It defaults
 * to Token::HTTP_HEADER.
 */
class Token extends Base {
	const HTTP_HEADER = 0;
	const QUERY_PARAMETER = 1;

	/**
	 * @var \HaveAPI\Client\Resource
	 */
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

		if (isSet($this->opts['token'])) {
			$this->configured = true;
			$this->token = $this->opts['token'];
			return;
		} elseif (isSet($this->opts['resume'])) {
			$r = $this->opts['resume'];
			$this->resumeAuthentication($r['action'], $r['token'], $r['input']);
			return;
		}

		$this->requestToken();
	}

	/**
	 * Resume multi-step authentication
	 * @param string $action
	 * @param string $token intermediate token
	 * @param array $input
	 */
	public function resumeAuthentication($action, $token, $input) {
		$this->runAuthentication($action, array_merge(
			$input,
			['token' => $token]
		));
	}

	/**
	 * Add token header if configured. Checks token validity.
	 * @param Request $request
	 */
	public function authenticate(Request $request) {
		if(!$this->configured)
			return;

		$this->checkValidity();

		if($this->via == self::HTTP_HEADER){
			$request->addHeader($this->description->http_header, $this->token);
		}
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
		$input = [
			'lifetime' => $this->opts['lifetime'] ?? 'renewable_auto',
			'interval' => $this->opts['interval'] ?? 300,
		];

		foreach ($this->getRequestCredentials() as $param) {
			if (isSet($this->opts[$param]))
				$input[$param] = $this->opts[$param];
		}

		$this->runAuthentication('request', $input);
	}

	/**
	 * Execute authentication steps until it succeeds, fails or is stopped
	 *
	 * The first step is executed immediately. All subsequent steps invoke the
	 * callback to get action credentials. The callback can also decide to stop
	 * or pause the authentication process.
	 * @param string $action
	 * @param array $input
	 */
	protected function runAuthentication($action, $input) {
		list($cont, $nextAction, $token) = $this->authenticationStep($action, $input);

		if ($cont == 'done')
			return;

		if (!isSet($this->opts['callback']) || !is_callable($this->opts['callback'])) {
			throw new BadFunctionCallException(
				'add callback to handle multi-step authentication'
			);
		}

		for (;;) {
			$cb = $this->opts['callback'](
				$nextAction,
				$token,
				$this->getCustomActionCredentials($nextAction)
			);

			if ($cb === 'stop') {
				return;
			} elseif (!is_array($cb)) {
				throw new RuntimeException("callback has to return an array or 'stop'");
			}

			$input = array_merge($cb, ['token' => $token]);

			list($cont, $nextAction, $token) = $this->authenticationStep($nextAction, $input);

			if ($cont == 'done')
				return;
		}
	}

	/**
	 * Perform one authentication step and return results
	 * @param string $action
	 * @param array $input
	 * @return array
	 */
	protected function authenticationStep($action, $input) {
		$ret = $this->rs->{$action}($input);

		if ($ret['complete']) {
			$this->token = $ret['token'];

			if($ret['valid_to'])
				$this->validTo = strtotime($ret['valid_to']);

			$this->configured = true;
			return ['done'];
		}

		return ['continue', $ret['next_action'], $ret['token']];
	}

	/**
	 * Return names of parameters used as credentials for action Request
	 * @return array
	 */
	protected function getRequestCredentials() {
		$ret = [];
		$params = $this->rs->request->getParameters('input');

		foreach ($params as $name => $desc) {
			if ($name != 'lifetime' && $params != 'interval')
				$ret[] = $name;
		}

		return $ret;
	}

	/**
	 * Return name and description of parameters used as credentials for custom
	 * authentication action
	 * @param string action
	 * @return array
	 */
	protected function getCustomActionCredentials($action) {
		$ret = [];
		$params = $this->rs->{$action}->getParameters('input');

		foreach ($params as $name => $desc) {
			if ($name != 'token')
				$ret[$name] = $desc;
		}

		return $ret;
	}

	/**
	 * Get a new token if the current one expired.
	 */
	protected function checkValidity() {
		if ($this->validTo && $this->validTo < time() && $this->hasRequestCredentials())
			$this->requestToken();
	}

	/**
	 * Check if all request credentials are provided
	 * @return boolean
	 */
	protected function hasRequestCredentials() {
		foreach ($this->getRequestCredentials() as $name) {
			if (!isSet($this->opts[$name]))
				return false;
		}

		return true;
	}

	/**
	 * Return the token resource
	 * @return \HaveAPI\Client\Resource
	 */
	public function getResource() {
		return $this->rs;
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

	/**
	 * Return true if the authentication process is complete
	 * @return boolean
	 */
	public function isComplete() {
		return $this->configured;
	}
}
