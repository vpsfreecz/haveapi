<?php

namespace HaveAPI\Client\AuthenticationProviders;

/**
 * Used when no authentication provider is selected. Does no authentication.
 */
class NoAuth extends Base {
	public function authenticate($request) {
		
	}
}
