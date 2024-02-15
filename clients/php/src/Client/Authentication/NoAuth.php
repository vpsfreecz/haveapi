<?php

namespace HaveAPI\Client\Authentication;

use Httpful\Request;

/**
 * Used when no authentication provider is selected. Does no authentication.
 */
class NoAuth extends Base
{
    public function authenticate(Request $request) {}
}
