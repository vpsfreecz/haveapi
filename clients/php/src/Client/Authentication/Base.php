<?php

namespace HaveAPI\Client\Authentication;

use HaveAPI\Client;
use Httpful\Request;

/**
 * Base class extended by all authentication providers.
 */
abstract class Base
{
    /**
     * @var Client
     */
    protected $client;

    /**
     * @var \stdClass
     */
    protected $description;

    /**
     * @var array
     */
    protected $opts;

    /**
     * @param Client $client
     * @param \stdClass $description description of this auth provider
     * @param array $opts options passed on to the provider
     */
    public function __construct(Client $client, $description, array $opts)
    {
        $this->client = $client;
        $this->description = $description;
        $this->opts = $opts;

        $this->setup();
    }

    /**
     * Called right after the constructor.
     * Overload it to setup your authentication provider.
     */
    protected function setup() {}

    /**
     * Authenticate request to the API.
     *
     * Called for every request sent to the API.
     * @param \Httpful\Request $request
     */
    abstract public function authenticate(Request $request);

    /**
     * Return query parameters to be sent in the request.
     *
     * Called for every request sent to the API.
     * @return array
     */
    public function queryParameters()
    {
        return [];
    }

    /**
     * Logout, revoke all tokens, cleanup.
     */
    public function logout() {}
}
