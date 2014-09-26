<?php

namespace HaveAPI\Client\Authentication;

/**
 * Used when no authentication provider is selected. Does no authentication.
 */
class NoAuth extends Base {
	public function authenticate($request) {
		
	}
}
