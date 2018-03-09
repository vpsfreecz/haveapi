<?php

namespace HaveAPI\Client\Authentication;
use Httpful\Request;

/**
 * Provider for HTTP basic authentication.
 * 
 * It accepts `username` and `password` as options.
 */
class Basic extends Base {

	public function authenticate(Request $request) {
		$request->authenticateWith($this->opts['username'], $this->opts['password']);
	}
}
