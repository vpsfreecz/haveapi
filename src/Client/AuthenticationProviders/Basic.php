<?php

namespace HaveAPI\Client\AuthenticationProviders;

/**
 * Provider for HTTP basic authentication.
 * 
 * It accepts `username` and `password` as options.
 */
class Basic extends Base {
	public function authenticate($request) {
		$request->authenticateWith($this->opts['username'], $this->opts['password']);
	}
}
